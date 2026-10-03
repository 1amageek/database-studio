import XCTest
import DatabaseKit
import DatabaseClientHTTP
import DatabaseWire
@testable import DatabaseStudioUI

/// Verifies real transport pagination over the externally retained financial dataset.
@MainActor
final class WorkspaceServerTests: XCTestCase {
    private struct Credential: Decodable { let endpoint: String; let token: String }

    func testRealServerFinancialQueryCollection() async throws {
        guard let credentialPath = ProcessInfo.processInfo.environment["STUDIO_WORKSPACE_CREDENTIAL"] else {
            throw XCTSkip("Requires the workspace-owned isolated server")
        }
        let credential = try JSONDecoder().decode(Credential.self, from: Data(contentsOf: URL(fileURLWithPath: credentialPath)))
        let endpoint = try XCTUnwrap(URL(string: credential.endpoint))
        let connection = RuntimeConnection()
        try await connection.connect(configuration: HTTPDatabaseConfiguration(endpoint: endpoint, accessToken: credential.token))
        do {
            let fixture = try XCTUnwrap(ProcessInfo.processInfo.environment["STUDIO_FINANCIAL_FIXTURE"])
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixture))) as? [String: Any])
            let companies = try XCTUnwrap(document["rows"] as? [[String: Any]])
            XCTAssertEqual(companies.count, 2000)
            let literals = try companies.map { company in
                let metrics = try XCTUnwrap(company["metrics"] as? [String: Any])
                var fields: [String] = []
                for key in ["company", "industry", "country"] {
                    let value = try XCTUnwrap(company[key] as? String)
                    fields.append(try quoted(value))
                }
                for key in ["revenueUSD", "netProfitUSD", "assetsUSD", "marketValueUSD"] {
                    if let value = metrics[key] as? NSNumber {
                        fields.append(try quoted(value.stringValue) + "^^xsd:double")
                    } else { fields.append("UNDEF") }
                }
                return "(" + fields.joined(separator: " ") + ")"
            }
            // VALUES supplies query data; this test grants no persisted entity access.
            let statement = "PREFIX xsd: <http://www.w3.org/2001/XMLSchema#> SELECT ?company ?industry ?country ?revenueUSD ?netProfitUSD ?assetsUSD ?marketValueUSD WHERE { VALUES (?company ?industry ?country ?revenueUSD ?netProfitUSD ?assetsUSD ?marketValueUSD) { " + literals.joined(separator: "\n") + " } }"
            let query = RuntimeQuery()
            await query.run(.init(input: .text(language: .sparql, statement: statement), page: .init(limit: 1000)), connection: connection)
            XCTAssertNil(query.failure)
            XCTAssertEqual(query.rows.count, 1000)
            XCTAssertTrue(query.hasNextPage)
            await query.loadRemainingPages(connection: connection)
            XCTAssertNil(query.failure)
            XCTAssertEqual(query.rows.count, 2000)
            XCTAssertFalse(query.hasNextPage)
            let presentation = try XCTUnwrap(query.presentation)
            await presentation.prepareAnalysis()
            XCTAssertEqual(presentation.analysisDataset?.document.nodes.count, 2000)
            XCTAssertNil(presentation.analysisFailure)
            await connection.disconnect()
        } catch {
            await connection.disconnect()
            throw error
        }
    }
    private func quoted(_ value: String) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: bytes, as: UTF8.self)
    }
}
