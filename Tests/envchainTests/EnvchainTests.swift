import XCTest
import Foundation

final class EnvchainTests: XCTestCase {
  private let testNamespace = "envchain-test-\(ProcessInfo.processInfo.processIdentifier)"

  private var binaryPath: String {
    // Find the built binary
    let buildDir = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(".build/debug/envchain")
      .path
    return buildDir
  }

  override func tearDown() {
    super.tearDown()
    // Clean up test keychain items
    _ = run(["--unset", testNamespace, "TEST_KEY"])
    _ = run(["--unset", testNamespace, "KEY_A"])
    _ = run(["--unset", testNamespace, "KEY_B"])
    _ = run(["--unset", testNamespace, "mixedCase_Key"])
    _ = run(["--unset", testNamespace, "AWS_ACCESS_KEY_ID"])
    _ = run(["--unset", testNamespace, "AWS_SECRET_ACCESS_KEY"])
    _ = run(["--unset", testNamespace, "AWS_SESSION_TOKEN"])
  }

  // MARK: - Helpers

  @discardableResult
  private func run(_ args: [String], input: String? = nil) -> (exitCode: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = args
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    if let input = input {
      let stdinPipe = Pipe()
      process.standardInput = stdinPipe
      stdinPipe.fileHandleForWriting.write(input.data(using: .utf8)!)
      stdinPipe.fileHandleForWriting.closeFile()
    }
    try! process.run()
    process.waitUntilExit()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    return (
      process.terminationStatus,
      String(data: stdoutData, encoding: .utf8) ?? "",
      String(data: stderrData, encoding: .utf8) ?? ""
    )
  }

  // MARK: - Tests

  func testNoArgsShowsHelp() {
    let result = run([])
    XCTAssertEqual(result.exitCode, 2)
    XCTAssertTrue(result.stderr.contains("Usage:"))
  }

  func testUnknownOption() {
    let result = run(["--invalid"])
    XCTAssertEqual(result.exitCode, 2)
    XCTAssertTrue(result.stderr.contains("Unknown option"))
  }

  func testSetAndListKeys() {
    let setResult = run(["--set", testNamespace, "TEST_KEY"], input: "secret_value\n")
    XCTAssertEqual(setResult.exitCode, 0)
    let listResult = run(["--list", testNamespace])
    XCTAssertEqual(listResult.exitCode, 0)
    XCTAssertTrue(listResult.stdout.contains("TEST_KEY"))
  }

  func testSetAndGetValue() {
    let setResult = run(["--set", testNamespace, "TEST_KEY"], input: "my_secret\n")
    XCTAssertEqual(setResult.exitCode, 0)
    let listResult = run(["--list", "-v", testNamespace])
    XCTAssertEqual(listResult.exitCode, 0)
    XCTAssertTrue(listResult.stdout.contains("TEST_KEY=my_secret"))
  }

  func testSetMultipleKeys() {
    let setResult = run(["--set", testNamespace, "KEY_A", "KEY_B"], input: "val_a\nval_b\n")
    XCTAssertEqual(setResult.exitCode, 0)
    let listResult = run(["--list", "-v", testNamespace])
    XCTAssertEqual(listResult.exitCode, 0)
    XCTAssertTrue(listResult.stdout.contains("KEY_A=val_a"))
    XCTAssertTrue(listResult.stdout.contains("KEY_B=val_b"))
  }

  func testUnset() {
    _ = run(["--set", testNamespace, "TEST_KEY"], input: "to_delete\n")
    let unsetResult = run(["--unset", testNamespace, "TEST_KEY"])
    XCTAssertEqual(unsetResult.exitCode, 0)
    let listResult = run(["--list", testNamespace])
    XCTAssertEqual(listResult.exitCode, 0)
    XCTAssertFalse(listResult.stdout.contains("TEST_KEY"))
  }

  func testExecSetsEnvVars() {
    _ = run(["--set", testNamespace, "TEST_KEY"], input: "exec_value\n")
    let execResult = run([testNamespace, "printenv", "TEST_KEY"])
    XCTAssertEqual(execResult.exitCode, 0)
    XCTAssertEqual(execResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "exec_value")
  }

  func testExecCommaNamespaces() {
    _ = run(["--set", testNamespace, "KEY_A"], input: "alpha\n")
    let execResult = run([testNamespace, "printenv", "KEY_A"])
    XCTAssertEqual(execResult.exitCode, 0)
    XCTAssertEqual(execResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "alpha")
  }

  func testExecUndefinedNamespaceWarns() {
    let result = run(["nonexistent-ns-\(testNamespace)", "printenv"])
    // Should still succeed (exec printenv) but warn on stderr
    XCTAssertTrue(result.stderr.contains("WARNING"))
  }

  func testListNamespaces() {
    _ = run(["--set", testNamespace, "TEST_KEY"], input: "val\n")
    let result = run(["--list"])
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stdout.contains(testNamespace))
  }

  func testOverwriteValue() {
    _ = run(["--set", testNamespace, "TEST_KEY"], input: "first\n")
    _ = run(["--set", testNamespace, "TEST_KEY"], input: "second\n")
    let listResult = run(["--list", "-v", testNamespace])
    XCTAssertEqual(listResult.exitCode, 0)
    XCTAssertTrue(listResult.stdout.contains("TEST_KEY=second"))
    XCTAssertFalse(listResult.stdout.contains("TEST_KEY=first"))
  }

  func testSetRequiresTooFewArgs() {
    let result = run(["--set", testNamespace])
    XCTAssertEqual(result.exitCode, 2)
  }

  func testUnsetRequiresTooFewArgs() {
    let result = run(["--unset", testNamespace])
    XCTAssertEqual(result.exitCode, 2)
  }

  func testExecRequiresCommand() {
    let result = run([testNamespace])
    XCTAssertEqual(result.exitCode, 2)
  }

  func testJSONOutput() {
    _ = run(["--set", testNamespace, "KEY_A", "KEY_B"], input: "val_a\nval_b\n")
    let result = run(["--json", testNamespace])
    XCTAssertEqual(result.exitCode, 0)
    let data = result.stdout.data(using: .utf8)!
    let dict = try! JSONSerialization.jsonObject(with: data) as! [String: String]
    XCTAssertEqual(dict["KEY_A"], "val_a")
    XCTAssertEqual(dict["KEY_B"], "val_b")
  }

  func testJSONPreservesKeyCase() {
    _ = run(["--set", testNamespace, "mixedCase_Key"], input: "hello\n")
    let result = run(["--json", testNamespace])
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "{\"mixedCase_Key\":\"hello\"}")
  }

  func testJSONUndefinedNamespace() {
    let result = run(["--json", "nonexistent-ns-\(testNamespace)"])
    XCTAssertEqual(result.exitCode, 1)
    XCTAssertTrue(result.stderr.contains("WARNING"))
  }

  func testAWSCredential() {
    _ = run(["--set", testNamespace, "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"], input: "AKID123\nsecret456\ntoken789\n")
    let result = run(["--aws-credential", testNamespace])
    XCTAssertEqual(result.exitCode, 0)
    let data = result.stdout.data(using: .utf8)!
    let cred = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(cred["Version"] as? Int, 1)
    XCTAssertEqual(cred["AccessKeyId"] as? String, "AKID123")
    XCTAssertEqual(cred["SecretAccessKey"] as? String, "secret456")
    XCTAssertEqual(cred["SessionToken"] as? String, "token789")
  }

  func testAWSCredentialWithoutOptionalFields() {
    _ = run(["--set", testNamespace, "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"], input: "AKID123\nsecret456\n")
    let result = run(["--aws-credential", testNamespace])
    XCTAssertEqual(result.exitCode, 0)
    let data = result.stdout.data(using: .utf8)!
    let cred = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(cred["Version"] as? Int, 1)
    XCTAssertEqual(cred["AccessKeyId"] as? String, "AKID123")
    XCTAssertEqual(cred["SecretAccessKey"] as? String, "secret456")
    XCTAssertNil(cred["SessionToken"])
    XCTAssertNil(cred["Expiration"])
  }

  func testAWSCredentialUndefinedNamespace() {
    let result = run(["--aws-credential", "nonexistent-ns-\(testNamespace)"])
    XCTAssertEqual(result.exitCode, 1)
    XCTAssertTrue(result.stderr.contains("WARNING"))
  }
}
