import Foundation

enum ClawixFrameworkResourceRoutes {
    static let appsDirectoryName = "apps"
    static let designDirectoryName = "design"
    static let documentsDirectoryName = "documents"
    static let stylesDirectoryName = "styles"
    static let templatesDirectoryName = "templates"
    static let referencesDirectoryName = "references"
    static let appManifestFileName = "manifest.json"
    static let editorDocumentFileName = "document.json"

    static func appsRootURL() -> URL {
        ClawixPersistentSurfacePaths.frameworkGlobalChild(appsDirectoryName, isDirectory: true)
    }

    static func designRootURL() -> URL {
        ClawixPersistentSurfacePaths.frameworkGlobalChild(designDirectoryName, isDirectory: true)
    }

    static func editorDocumentsRootURL(designRootURL: URL = designRootURL()) -> URL {
        designRootURL.appendingPathComponent(documentsDirectoryName, isDirectory: true)
    }

    static func stylesRootURL(designRootURL: URL) -> URL {
        designRootURL.appendingPathComponent(stylesDirectoryName, isDirectory: true)
    }

    static func templatesRootURL(designRootURL: URL) -> URL {
        designRootURL.appendingPathComponent(templatesDirectoryName, isDirectory: true)
    }

    static func referencesRootURL(designRootURL: URL) -> URL {
        designRootURL.appendingPathComponent(referencesDirectoryName, isDirectory: true)
    }

    static func styleDirectory(styleId: String, stylesRootURL: URL) -> URL {
        stylesRootURL.appendingPathComponent(styleId, isDirectory: true)
    }

    static func templateDirectory(templateId: String, templatesRootURL: URL) -> URL {
        templatesRootURL.appendingPathComponent(templateId, isDirectory: true)
    }

    static func referenceDirectory(referenceId: String, referencesRootURL: URL) -> URL {
        referencesRootURL.appendingPathComponent(referenceId, isDirectory: true)
    }

    static func appDirectory(appId: String, appsRootURL: URL) -> URL {
        appsRootURL.appendingPathComponent(appId, isDirectory: true)
    }

    static func editorDocumentDirectory(documentId: String, documentsRootURL: URL) -> URL {
        documentsRootURL.appendingPathComponent(documentId, isDirectory: true)
    }

    static func editorDocumentManifestURL(documentDirectory: URL) -> URL {
        documentDirectory.appendingPathComponent(editorDocumentFileName, isDirectory: false)
    }
}
