import Foundation
import XCTest

final class EnvchainTests: XCTestCase {
  private let testNamespace1 =
    "envchain-test1-\(ProcessInfo.processInfo.processIdentifier)"
  private let testNamespace2 =
    "envchain-test2-\(ProcessInfo.processInfo.processIdentifier)"

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
    _ = run(["--unset", testNamespace1, "TEST_KEY"])
    _ = run(["--unset", testNamespace1, "KEY_A"])
    _ = run(["--unset", testNamespace1, "KEY_B"])
    _ = run(["--unset", testNamespace1, "mixedCase_Key"])
    _ = run(["--unset", testNamespace1, "AWS_ACCESS_KEY_ID"])
    _ = run(["--unset", testNamespace1, "AWS_SECRET_ACCESS_KEY"])
    _ = run(["--unset", testNamespace1, "AWS_SESSION_TOKEN"])
    _ = run(["--unset", testNamespace2, "KEY_B"])
  }

  // MARK: - Helpers

  @discardableResult
  private func run(_ args: [String], input: String? = nil) -> (
    exitCode: Int32, stdout: String, stderr: String
  ) {
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
    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(
      result.stderr.contains("USAGE:") || result.stderr.contains("Usage:"))
  }

  func testUnknownOption() {
    let result = run(["--invalid"])
    XCTAssertNotEqual(result.exitCode, 0)
  }

  func testSetAndListKeys() {
    let setResult = run(
      ["--set", testNamespace1, "TEST_KEY"], input: "secret_value\n")
    XCTAssertEqual(setResult.exitCode, 0)
    let listResult = run(["--list", testNamespace1])
    XCTAssertEqual(listResult.exitCode, 0)
    XCTAssertTrue(listResult.stdout.contains("TEST_KEY"))
  }

  func testSetAndGetValue() {
    let setResult = run(
      ["--set", testNamespace1, "TEST_KEY"], input: "my_secret\n")
    XCTAssertEqual(setResult.exitCode, 0)
    let listResult = run(["--list", "-v", testNamespace1])
    XCTAssertEqual(listResult.exitCode, 0)
    XCTAssertTrue(listResult.stdout.contains("TEST_KEY=my_secret"))
  }

  func testSetMultipleKeys() {
    let setResult = run(
      ["--set", testNamespace1, "KEY_A", "KEY_B"], input: "val_a\nval_b\n")
    XCTAssertEqual(setResult.exitCode, 0)
    let listResult = run(["--list", "-v", testNamespace1])
    XCTAssertEqual(listResult.exitCode, 0)
    XCTAssertTrue(listResult.stdout.contains("KEY_A=val_a"))
    XCTAssertTrue(listResult.stdout.contains("KEY_B=val_b"))
  }

  func testUnset() {
    _ = run(["--set", testNamespace1, "TEST_KEY"], input: "to_delete\n")
    let unsetResult = run(["--unset", testNamespace1, "TEST_KEY"])
    XCTAssertEqual(unsetResult.exitCode, 0)
    let listResult = run(["--list", testNamespace1])
    XCTAssertEqual(listResult.exitCode, 0)
    XCTAssertFalse(listResult.stdout.contains("TEST_KEY"))
  }

  func testExecSetsEnvVars() {
    _ = run(["--set", testNamespace1, "TEST_KEY"], input: "exec_value\n")
    let execResult = run([testNamespace1, "printenv", "TEST_KEY"])
    XCTAssertEqual(execResult.exitCode, 0)
    XCTAssertEqual(
      execResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
      "exec_value")
  }

  func testExecCommaNamespaces() {
    _ = run(["--set", testNamespace1, "KEY_A"], input: "alpha\n")
    _ = run(["--set", testNamespace2, "KEY_B"], input: "beta\n")
    let execResult = run([
      "\(testNamespace1),\(testNamespace2)",
      "sh", "-c", "echo $KEY_A:$KEY_B",
    ])
    XCTAssertEqual(execResult.exitCode, 0)
    let output = execResult.stdout.trimmingCharacters(
      in: .whitespacesAndNewlines)
    XCTAssertEqual(output, "alpha:beta")
  }

  func testExecUndefinedNamespaceWarns() {
    let result = run(["nonexistent-ns-\(testNamespace1)", "printenv"])
    // Should still succeed (exec printenv) but warn on stderr
    XCTAssertTrue(result.stderr.contains("WARNING"))
  }

  func testListNamespaces() {
    _ = run(["--set", testNamespace1, "TEST_KEY"], input: "val\n")
    let result = run(["--list"])
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stdout.contains(testNamespace1))
  }

  func testOverwriteValue() {
    _ = run(["--set", testNamespace1, "TEST_KEY"], input: "first\n")
    _ = run(["--set", testNamespace1, "TEST_KEY"], input: "second\n")
    let listResult = run(["--list", "-v", testNamespace1])
    XCTAssertEqual(listResult.exitCode, 0)
    XCTAssertTrue(listResult.stdout.contains("TEST_KEY=second"))
    XCTAssertFalse(listResult.stdout.contains("TEST_KEY=first"))
  }

  func testSetRequiresTooFewArgs() {
    let result = run(["--set", testNamespace1])
    XCTAssertNotEqual(result.exitCode, 0)
  }

  func testUnsetRequiresTooFewArgs() {
    let result = run(["--unset", testNamespace1])
    XCTAssertNotEqual(result.exitCode, 0)
  }

  func testExecRequiresCommand() {
    let result = run([testNamespace1])
    XCTAssertNotEqual(result.exitCode, 0)
  }

  func testJSONOutput() {
    _ = run(
      ["--set", testNamespace1, "KEY_A", "KEY_B"], input: "val_a\nval_b\n")
    let result = run(["--json", testNamespace1])
    XCTAssertEqual(result.exitCode, 0)
    let data = result.stdout.data(using: .utf8)!
    let dict =
      try! JSONSerialization.jsonObject(with: data) as! [String: String]
    XCTAssertEqual(dict["KEY_A"], "val_a")
    XCTAssertEqual(dict["KEY_B"], "val_b")
  }

  func testJSONPreservesKeyCase() {
    _ = run(["--set", testNamespace1, "mixedCase_Key"], input: "hello\n")
    let result = run(["--json", testNamespace1])
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(
      result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
      "{\"mixedCase_Key\":\"hello\"}")
  }

  func testJSONUndefinedNamespace() {
    let result = run(["--json", "nonexistent-ns-\(testNamespace1)"])
    XCTAssertEqual(result.exitCode, 1)
    XCTAssertTrue(result.stderr.contains("WARNING"))
  }

  func testAWSCredential() {
    _ = run(
      [
        "--set", testNamespace1, "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
      ],
      input: "AKID123\nsecret456\ntoken789\n")
    let result = run(["--aws-credential", testNamespace1])
    XCTAssertEqual(result.exitCode, 0)
    let data = result.stdout.data(using: .utf8)!
    let cred = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(cred["Version"] as? Int, 1)
    XCTAssertEqual(cred["AccessKeyId"] as? String, "AKID123")
    XCTAssertEqual(cred["SecretAccessKey"] as? String, "secret456")
    XCTAssertEqual(cred["SessionToken"] as? String, "token789")
  }

  func testAWSCredentialWithoutOptionalFields() {
    _ = run(
      ["--set", testNamespace1, "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"],
      input: "AKID123\nsecret456\n")
    let result = run(["--aws-credential", testNamespace1])
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
    let result = run(["--aws-credential", "nonexistent-ns-\(testNamespace1)"])
    XCTAssertEqual(result.exitCode, 1)
    XCTAssertTrue(result.stderr.contains("WARNING"))
  }

  // MARK: - Env key validation tests

  func testValidEnvKeyAcceptsUppercase() {
    let result = run(["--set", testNamespace1, "FOO"], input: "val\n")
    XCTAssertEqual(result.exitCode, 0)
    _ = run(["--unset", testNamespace1, "FOO"])
  }

  func testValidEnvKeyAcceptsUnderscorePrefix() {
    let result = run(["--set", testNamespace1, "_BAR2"], input: "val\n")
    XCTAssertEqual(result.exitCode, 0)
    _ = run(["--unset", testNamespace1, "_BAR2"])
  }

  func testInvalidEnvKeyRejectsDigitStart() {
    let result = run(["--set", testNamespace1, "1BADKEY"], input: "val\n")
    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Invalid environment variable name"))
  }

  func testInvalidEnvKeyRejectsDash() {
    let result = run(["--set", testNamespace1, "BAD-NAME"], input: "val\n")
    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Invalid environment variable name"))
  }

  func testInvalidEnvKeyRejectsSpace() {
    let result = run(["--set", testNamespace1, "BAD NAME"], input: "val\n")
    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Invalid environment variable name"))
  }

  func testDeniedEnvKeyLDPreload() {
    let result = run(["--set", testNamespace1, "LD_PRELOAD"], input: "val\n")
    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Invalid environment variable name"))
  }

  func testDeniedEnvKeyDYLDInsertLibraries() {
    let result = run(
      ["--set", testNamespace1, "DYLD_INSERT_LIBRARIES"], input: "val\n")
    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Invalid environment variable name"))
  }
}
