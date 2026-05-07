import Foundation
import ProtonCore

var passed = 0
var failed = 0

@MainActor func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        print("  ✓ \(name)")
        passed += 1
    } catch {
        print("  ✗ \(name): \(error)")
        failed += 1
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    guard a == b else {
        throw TestError.notEqual("\(a) != \(b) at \(file):\(line)")
    }
}

func assertNotEqual<T: Equatable>(_ a: T, _ b: T) throws {
    guard a != b else { throw TestError.notEqual("values should differ") }
}

func assertTrue(_ v: Bool) throws {
    guard v else { throw TestError.notEqual("expected true") }
}

func assertFalse(_ v: Bool) throws {
    guard !v else { throw TestError.notEqual("expected false") }
}

enum TestError: Error {
    case notEqual(String)
}

// MARK: - ExpandHash Tests
print("\n=== ExpandHash Tests ===")

test("produces 256 bytes") {
    let result = ExpandHash.hash(Data("test".utf8))
    try assertEqual(result.count, 256)
}

test("is deterministic") {
    let r1 = ExpandHash.hash(Data("hello".utf8))
    let r2 = ExpandHash.hash(Data("hello".utf8))
    try assertEqual(r1, r2)
}

test("different inputs differ") {
    let r1 = ExpandHash.hash(Data("a".utf8))
    let r2 = ExpandHash.hash(Data("b".utf8))
    try assertNotEqual(r1, r2)
}

// MARK: - Bcrypt Tests
print("\n=== Bcrypt Tests ===")

test("produces 23 bytes") {
    let result = Bcrypt.hash(password: Array("password".utf8), salt: [UInt8](repeating: 0, count: 16), cost: 4)
    try assertEqual(result.count, 23)
}

test("is deterministic") {
    let salt: [UInt8] = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]
    let r1 = Bcrypt.hash(password: Array("test".utf8), salt: salt, cost: 4)
    let r2 = Bcrypt.hash(password: Array("test".utf8), salt: salt, cost: 4)
    try assertEqual(r1, r2)
}

test("different passwords differ") {
    let salt = [UInt8](repeating: 0x42, count: 16)
    let r1 = Bcrypt.hash(password: Array("pass1".utf8), salt: salt, cost: 4)
    let r2 = Bcrypt.hash(password: Array("pass2".utf8), salt: salt, cost: 4)
    try assertNotEqual(r1, r2)
}

// MARK: - ModulusParser Tests
print("\n=== ModulusParser Tests ===")

test("extracts base64 from PGP clearsigned") {
    let msg = """
    -----BEGIN PGP SIGNED MESSAGE-----
    Hash: SHA256

    dGVzdCBtb2R1bHVz
    -----BEGIN PGP SIGNATURE-----
    fakesig==
    -----END PGP SIGNATURE-----
    """
    let data = try ModulusParser.decode(msg)
    try assertEqual(String(data: data, encoding: .utf8), "test modulus")
}

// MARK: - SRPClient Tests
print("\n=== SRPClient Tests ===")

test("server proof verification match") {
    let proof = Data([1, 2, 3]).base64EncodedString()
    try assertTrue(SRPClient.verifyServerProof(proof, expected: proof))
}

test("server proof verification mismatch") {
    let p1 = Data([1, 2, 3]).base64EncodedString()
    let p2 = Data([4, 5, 6]).base64EncodedString()
    try assertFalse(SRPClient.verifyServerProof(p1, expected: p2))
}

// MARK: - PasswordHash Tests
print("\n=== PasswordHash Tests ===")

test("v3 produces 256 bytes") {
    let result = try PasswordHash.hash(
        password: Data("testpwd".utf8),
        salt: Data([UInt8](repeating: 0xAB, count: 16)),
        modulus: Data([UInt8](repeating: 0xCD, count: 256)),
        version: 3
    )
    try assertEqual(result.count, 256)
}

test("v0 produces 256 bytes") {
    let result = try PasswordHash.hash(
        password: Data("testpwd".utf8),
        salt: Data([UInt8](repeating: 0xAB, count: 16)),
        modulus: Data([UInt8](repeating: 0xCD, count: 256)),
        version: 0
    )
    try assertEqual(result.count, 256)
}

// MARK: - Live API Test (auth/info only, no login)
print("\n=== Live API Test ===")

@MainActor func runLiveTest() async {
    do {
        let url = URL(string: "https://mail.proton.me/api/auth/info")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Other", forHTTPHeaderField: "x-pm-appversion")
        req.httpBody = try JSONEncoder().encode(AuthInfoRequest(Username: "test@proton.me"))

        let (data, response) = try await URLSession.shared.data(for: req)
        let httpResp = response as! HTTPURLResponse
        print("  HTTP status: \(httpResp.statusCode)")

        let info = try JSONDecoder().decode(AuthInfoResponse.self, from: data)
        print("  SRP version: \(info.version)")
        print("  Salt length: \(info.salt.count) chars")
        print("  ServerEphemeral present: \(!info.serverEphemeral.isEmpty)")
        print("  Modulus starts with PGP: \(info.modulus.hasPrefix("-----BEGIN PGP"))")
        print("  SRPSession: \(info.srpSession.prefix(8))...")

        let modulus = try ModulusParser.decode(info.modulus)
        print("  Modulus decoded: \(modulus.count) bytes")

        print("  ✓ Live API test passed")
        passed += 1
    } catch {
        print("  ✗ Live API test failed: \(error)")
        failed += 1
    }
}

// Run the async test
let semaphore = DispatchSemaphore(value: 0)
Task {
    await runLiveTest()
    semaphore.signal()
}
semaphore.wait()

// MARK: - Summary
print("\n=== Results ===")
print("\(passed) passed, \(failed) failed")

if failed > 0 {
    exit(1)
}
