import XCTest
@testable import Helper

final class GmailOAuthServiceTests: XCTestCase {
    @MainActor
    func testCodeVerifierAndChallengeArePKCECompatible() {
        let verifier = GmailOAuthService.makeCodeVerifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)

        let challenge = GmailOAuthService.makeCodeChallenge(codeVerifier: verifier)
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
    }

    @MainActor
    func testParseCallbackURLExtractsCodeAndState() throws {
        let url = try XCTUnwrap(URL(string: "helper-oauth://oauth/gmail/callback?code=abc123&state=xyz987"))
        let parsed = GmailOAuthService.parseCallbackURL(url)

        XCTAssertEqual(parsed.code, "abc123")
        XCTAssertEqual(parsed.state, "xyz987")
    }
}
