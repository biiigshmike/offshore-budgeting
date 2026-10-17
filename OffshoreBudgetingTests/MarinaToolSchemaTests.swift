import Foundation
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels

@MainActor
struct MarinaToolSchemaTests {
    @Test func registeredToolsHaveDistinctGeneratedSchemaNames() throws {
        let schemas = [MarinaFindRecordsTool.Arguments.generationSchema,
                       MarinaExpensesTool.Arguments.generationSchema,
                       MarinaIncomeTool.Arguments.generationSchema,
                       MarinaBudgetTool.Arguments.generationSchema,
                       MarinaAccountsTool.Arguments.generationSchema]
        let titles = try schemas.map { schema in
            let object = try #require(JSONSerialization.jsonObject(with: Data(schema.debugDescription.utf8)) as? [String: Any])
            return try #require(object["title"] as? String)
        }
        #expect(Set(titles).count == schemas.count)
        #expect(!titles.contains("Arguments"))
    }

    @Test func sharedSchemaDefinitionNamesNeverHaveDifferentShapes() throws {
        let schemas = [MarinaFindRecordsTool.Arguments.generationSchema,
                       MarinaExpensesTool.Arguments.generationSchema,
                       MarinaIncomeTool.Arguments.generationSchema,
                       MarinaBudgetTool.Arguments.generationSchema,
                       MarinaAccountsTool.Arguments.generationSchema]
        var definitions: [String: Data] = [:]
        for schema in schemas {
            let root = try #require(JSONSerialization.jsonObject(with: Data(schema.debugDescription.utf8)) as? [String: Any])
            for (name, definition) in root["$defs"] as? [String: Any] ?? [:] {
                let encoded = try JSONSerialization.data(withJSONObject: definition, options: [.sortedKeys])
                if let existing = definitions[name] {
                    #expect(existing == encoded, "Generated definition \(name) has incompatible shapes across registered tools.")
                } else { definitions[name] = encoded }
            }
        }
    }
}
#endif
