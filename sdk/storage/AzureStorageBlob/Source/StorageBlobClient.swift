// --------------------------------------------------------------------------
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//
// The MIT License (MIT)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the ""Software""), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
//
// --------------------------------------------------------------------------

import AzureCore
import Foundation

/// A StorageBlobClient represents a Client to the Azure Storage Blob service allowing you to manipulate blobs within
/// storage containers.
public final class StorageBlobClient: PipelineClient {
    /// API version of the Azure Storage Blob service to invoke. Defaults to the latest.
    public enum ApiVersion: String {
        /// The most recent API version of the Azure Storabe Blob service
        case latest = "2019-02-02"
    }

    /// The global maximum number of managed transfers that will be executed concurrently by all `StorageBlobClient`
    /// instances. The default value is `maxConcurrentTransfersDefaultValue`. To allow this value to be determined
    /// dynamically based on current system conditions, set it to `maxConcurrentTransfersDynamicValue`.
    public static var maxConcurrentTransfers: Int {
        get { return manager.maxConcurrency }
        set { manager.maxConcurrency = newValue }
    }

    /// The default value of `maxConcurrentTransfers`.
    public static let maxConcurrentTransfersDefaultValue = 4

    /// Set `maxConcurrentTransfers` equal to this value to allow the maximum number of managed transfers to be
    /// determined dynamically based on current system conditions.
    public static let maxConcurrentTransfersDynamicValue = OperationQueue.defaultMaxConcurrentOperationCount

    /// Options provided to configure this `StorageBlobClient`.
    public let options: StorageBlobClientOptions

    /// The `TransferDelegate` to inform about events from transfers created by this `StorageBlobClient`.
    public weak var transferDelegate: TransferDelegate?

    private static let defaultScopes = [
        "https://storage.azure.com/.default"
    ]

    private static let manager: TransferManager = URLSessionTransferManager.shared

    private let restorationId: String

    // MARK: Initializers

    /// Create a Storage blob data client.
    /// - Parameters:
    ///   - baseUrl: Base URL for the storage account.
    ///   - authPolicy: An `Authenticating` policy to use for authenticating client requests.
    ///   - restorationId: An identifier used to associate this client with transfers it creates. When a transfer is
    ///     reloaded from disk (e.g. after an application crash), it can only be resumed once a client with the same
    ///     `restorationId` has been initialized. If your application only uses a single `StorageBlobClient`, it is
    ///     recommended to use a value unique to your application (e.g. "MyApplication"). If your application uses
    ///     multiple clients with different configurations, use a value unique to both your application and the
    ///     configuration (e.g. "MyApplication.userClient").
    ///   - options: Options used to configure the client.
    private init(
        baseUrl: URL,
        authPolicy: Authenticating,
        withRestorationId restorationId: String,
        withOptions options: StorageBlobClientOptions? = nil
    ) throws {
        self.options = options ?? StorageBlobClientOptions(apiVersion: ApiVersion.latest.rawValue)
        self.restorationId = restorationId
        super.init(
            baseUrl: baseUrl,
            transport: URLSessionTransport(),
            policies: [
                UserAgentPolicy(for: StorageBlobClient.self),
                RequestIdPolicy(),
                AddDatePolicy(),
                authPolicy,
                ContentDecodePolicy(),
                LoggingPolicy(
                    allowHeaders: StorageBlobClient.allowHeaders,
                    allowQueryParams: StorageBlobClient.allowQueryParams
                )
            ],
            logger: self.options.logger
        )
        try StorageBlobClient.manager.register(client: self, forRestorationId: restorationId)
    }

    /// Create a Storage blob data client.
    /// - Parameters:
    ///   - accountUrl: Base URL for the storage account.
    ///   - credential: A `MSALCredential` object used to retrieve authentication tokens.
    ///   - restorationId: An identifier used to associate this client with transfers it creates. When a transfer is
    ///     reloaded from disk (e.g. after an application crash), it can only be resumed once a client with the same
    ///     `restorationId` has been initialized. If your application only uses a single `StorageBlobClient`, it is
    ///     recommended to use a value unique to your application (e.g. "MyApplication"). If your application uses
    ///     multiple clients with different configurations, use a value unique to both your application and the
    ///     configuration (e.g. "MyApplication.userClient").
    ///   - options: Options used to configure the client.
    public convenience init(
        accountUrl: URL,
        credential: MSALCredential,
        withRestorationId restorationId: String,
        withOptions options: StorageBlobClientOptions? = nil
    ) throws {
        let authPolicy = BearerTokenCredentialPolicy(credential: credential, scopes: StorageBlobClient.defaultScopes)
        try self
            .init(baseUrl: accountUrl, authPolicy: authPolicy, withRestorationId: restorationId, withOptions: options)
    }

    /// Create a Storage blob data client.
    /// - Parameters:
    ///   - credential: A `StorageSASCredential` object used to retrieve the base URL and authentication tokens.
    ///   - restorationId: An identifier used to associate this client with transfers it creates. When a transfer is
    ///     reloaded from disk (e.g. after an application crash), it can only be resumed once a client with the same
    ///     `restorationId` has been initialized. If your application only uses a single `StorageBlobClient`, it is
    ///     recommended to use a value unique to your application (e.g. "MyApplication"). If your application uses
    ///     multiple clients with different configurations, use a value unique to both your application and the
    ///     configuration (e.g. "MyApplication.userClient").
    ///   - options: Options used to configure the client.
    public convenience init(
        credential: StorageSASCredential,
        withRestorationId restorationId: String,
        withOptions options: StorageBlobClientOptions? = nil
    ) throws {
        guard let blobEndpoint = credential.blobEndpoint else {
            throw AzureError.serviceRequest("Invalid connection string. No blob endpoint specified.")
        }
        guard let baseUrl = URL(string: blobEndpoint) else {
            throw AzureError.fileSystem("Unable to resolve account URL from credential.")
        }
        let authPolicy = StorageSASAuthenticationPolicy(credential: credential)
        try self.init(baseUrl: baseUrl, authPolicy: authPolicy, withRestorationId: restorationId, withOptions: options)
    }

    /// Create a Storage blob data client.
    /// - Parameters:
    ///   - connectionString: Storage account connection string. **WARNING**: Connection strings are inherently insecure
    ///     in a mobile app. Any connection strings used should be read-only and not have write permissions.
    ///   - restorationId: An identifier used to associate this client with transfers it creates. When a transfer is
    ///     reloaded from disk (e.g. after an application crash), it can only be resumed once a client with the same
    ///     `restorationId` has been initialized. If your application only uses a single `StorageBlobClient`, it is
    ///     recommended to use a value unique to your application (e.g. "MyApplication"). If your application uses
    ///     multiple clients with different configurations, use a value unique to both your application and the
    ///     configuration (e.g. "MyApplication.userClient").
    ///   - options: Options used to configure the client.
    public convenience init(
        connectionString: String,
        withRestorationId restorationId: String,
        withOptions options: StorageBlobClientOptions? = nil
    ) throws {
        let credential = try StorageSASCredential(connectionString: connectionString)
        try self.init(credential: credential, withRestorationId: restorationId, withOptions: options)
    }

    // MARK: Public Client Methods

    /// List storage containers in a storage account.
    /// - Parameters:
    ///   - options: A `ListContainersOptions` object to control the list operation.
    ///   - completion: A completion handler that receives a `PagedCollection` of `ContainerItem` objects on success.
    public func listContainers(
        withOptions options: ListContainersOptions? = nil,
        then completion: @escaping HTTPResultHandler<PagedCollection<ContainerItem>>
    ) {
        // Construct URL
        let urlTemplate = ""
        guard let url = self.url(forTemplate: urlTemplate) else { return }

        // Construct query
        var queryParams: [QueryParameter] = [("comp", "list")]

        // Construct headers
        var headers = HTTPHeaders([
            .accept: "application/xml",
            .apiVersion: self.options.apiVersion
        ])

        // Process endpoint options
        if let options = options {
            // Query options
            if let prefix = options.prefix { queryParams.append("prefix", prefix) }
            if let include = options.include {
                queryParams.append("include", (include.map { $0.rawValue }).joined(separator: ","))
            }
            if let maxResults = options.maxResults { queryParams.append("maxresults", String(maxResults)) }
            if let timeout = options.timeout { queryParams.append("timeout", String(timeout)) }

            // Header options
            if let clientRequestId = options.clientRequestId {
                headers[HTTPHeader.clientRequestId] = clientRequestId
            }
        }

        // Construct and send request
        let codingKeys = PagedCodingKeys(
            items: "EnumerationResults.Containers",
            continuationToken: "EnumerationResults.NextMarker",
            xmlItemName: "Container"
        )
        let xmlMap = XMLMap(withPagedCodingKeys: codingKeys, innerType: ContainerItem.self)
        let context = PipelineContext.of(keyValues: [
            ContextKey.xmlMap.rawValue: xmlMap as AnyObject
        ])
        guard let request = try? HTTPRequest(method: .get, url: url, headers: headers) else { return }
        request.add(queryParams: queryParams)

        self.request(request, context: context) { result, httpResponse in
            switch result {
            case let .success(data):
                guard let data = data else {
                    let noDataError = HTTPResponseError.decode("Response data expected but not found.")
                    completion(.failure(noDataError), httpResponse)
                    return
                }
                do {
                    let decoder = StorageJSONDecoder()
                    let paged = try PagedCollection<ContainerItem>(
                        client: self,
                        request: request,
                        data: data,
                        codingKeys: codingKeys,
                        decoder: decoder,
                        delegate: self
                    )
                    completion(.success(paged), httpResponse)
                } catch {
                    completion(.failure(error), httpResponse)
                }
            case let .failure(error):
                completion(.failure(error), httpResponse)
            }
        }
    }

    /// List blobs within a storage container.
    /// - Parameters:
    ///   - container: The container name containing the blobs to list.
    ///   - options: A `ListBlobsOptions` object to control the list operation.
    ///   - completion: A completion handler that receives a `PagedCollection` of `BlobItem` objects on success.
    public func listBlobs(
        inContainer container: String,
        withOptions options: ListBlobsOptions? = nil,
        then completion: @escaping HTTPResultHandler<PagedCollection<BlobItem>>
    ) {
        // Construct URL
        let urlTemplate = "{container}"
        let pathParams = [
            "container": container
        ]
        guard let url = self.url(forTemplate: urlTemplate, withKwargs: pathParams) else { return }

        // Construct query
        var queryParams: [QueryParameter] = [
            ("comp", "list"),
            ("resType", "container")
        ]

        // Construct headers
        var headers = HTTPHeaders([
            .accept: "application/xml",
            .transferEncoding: "chunked",
            .apiVersion: self.options.apiVersion
        ])

        // Process endpoint options
        if let options = options {
            // Query options
            if let prefix = options.prefix { queryParams.append("prefix", prefix) }
            if let delimiter = options.delimiter { queryParams.append("delimiter", delimiter) }
            if let include = options.include {
                queryParams.append("include", (include.map { $0.rawValue }).joined(separator: ","))
            }
            if let maxResults = options.maxResults { queryParams.append("maxresults", String(maxResults)) }
            if let timeout = options.timeout { queryParams.append("timeout", String(timeout)) }

            // Header options
            if let clientRequestId = options.clientRequestId {
                headers[.clientRequestId] = clientRequestId
            }
        }

        // Construct and send request
        guard let request = try? HTTPRequest(method: .get, url: url, headers: headers) else { return }
        request.add(queryParams: queryParams)
        let codingKeys = PagedCodingKeys(
            items: "EnumerationResults.Blobs",
            continuationToken: "EnumerationResults.NextMarker",
            xmlItemName: "Blob"
        )
        let xmlMap = XMLMap(withPagedCodingKeys: codingKeys, innerType: BlobItem.self)
        let context = PipelineContext.of(keyValues: [
            ContextKey.xmlMap.rawValue: xmlMap as AnyObject
        ])
        self.request(request, context: context) { result, httpResponse in
            switch result {
            case let .success(data):
                guard let data = data else {
                    let noDataError = HTTPResponseError.decode("Response data expected but not found.")
                    completion(.failure(noDataError), httpResponse)
                    return
                }
                do {
                    let decoder = StorageJSONDecoder()
                    let paged = try PagedCollection<BlobItem>(
                        client: self,
                        request: request,
                        data: data,
                        codingKeys: codingKeys,
                        decoder: decoder,
                        delegate: self
                    )
                    completion(.success(paged), httpResponse)
                } catch {
                    completion(.failure(error), httpResponse)
                }
            case let .failure(error):
                completion(.failure(error), httpResponse)
            }
        }
    }

    /// Download a blob from a storage container.
    ///
    /// This method will execute a raw HTTP GET in order to download a single blob to the destination. It is
    /// **STRONGLY** recommended that you use the `download()` method instead - that method will manage the transfer in
    /// the face of changing network conditions, and is able to transfer multiple blocks in parallel.
    /// - Parameters:
    ///   - blob: The name of the blob.
    ///   - container: The name of the container.
    ///   - destinationUrl: The URL to a file path on this device.
    ///   - options: A `DownloadBlobOptions` object to control the download operation.
    ///   - completion: A completion handler that receives a `BlobDownloader` object on success.
    public func rawDownload(
        blob: String,
        fromContainer container: String,
        toFile destinationUrl: URL,
        withOptions options: DownloadBlobOptions? = nil,
        then completion: @escaping HTTPResultHandler<BlobDownloader>
    ) throws {
        // Construct URL
        let urlTemplate = "/{container}/{blob}"
        let pathParams = [
            "container": container,
            "blob": blob
        ]
        guard let url = self.url(forTemplate: urlTemplate, withKwargs: pathParams) else { return }

        let downloader = try BlobStreamDownloader(
            client: self,
            source: url,
            destination: destinationUrl,
            options: options
        )
        downloader.initialRequest { result, httpResponse in
            switch result {
            case .success:
                completion(.success(downloader), httpResponse)
            case let .failure(error):
                completion(.failure(error), httpResponse)
            }
        }
    }

    /// Upload a blob to a storage container.
    ///
    /// This method will execute a raw HTTP PUT in order to upload a single file to the destination. It is **STRONGLY**
    /// recommended that you use the `upload()` method instead - that method will manage the transfer in the face of
    /// changing network conditions, and is able to transfer multiple blocks in parallel.
    /// - Parameters:
    ///   - sourceUrl: The URL to a file on this device
    ///   - container: The name of the container.
    ///   - blob: The name of the blob.
    ///   - properties: Properties to set on the resulting blob.
    ///   - options: An `UploadBlobOptions` object to control the upload operation.
    ///   - completion: A completion handler that receives a `BlobUploader` object on success.
    public func rawUpload(
        file sourceUrl: URL,
        toContainer container: String,
        asBlob blob: String,
        properties: BlobProperties? = nil,
        withOptions options: UploadBlobOptions? = nil,
        then completion: @escaping HTTPResultHandler<BlobUploader>
    ) throws {
        // Construct URL
        let urlTemplate = "/{container}/{blob}"
        let pathParams = [
            "container": container,
            "blob": blob
        ]
        guard let url = self.url(forTemplate: urlTemplate, withKwargs: pathParams) else { return }

        let uploader = try BlobStreamUploader(
            client: self,
            source: sourceUrl,
            destination: url,
            properties: properties,
            options: options
        )
        uploader.next { result, httpResponse in
            switch result {
            case .success:
                completion(.success(uploader), httpResponse)
            case let .failure(error):
                completion(.failure(error), httpResponse)
            }
        }
    }

    /// Reliably download a blob from a storage container.
    ///
    /// This method will reliably manage the transfer of the blob from the cloud service to this device. When called,
    /// a transfer will be queued and a `Transfer` object will be returned that provides a handle to the transfer. This
    /// client's `transferDelegate` will be notified about state changes for all transfers managed by the client.
    /// - Parameters:
    ///   - blob: The name of the blob.
    ///   - container: The name of the container.
    ///   - destinationUrl: The URL to a file path on this device.
    ///   - options: A `DownloadBlobOptions` object to control the download operation.
    public func download(
        blob: String,
        fromContainer container: String,
        toFile destinationUrl: URL,
        withOptions options: DownloadBlobOptions? = nil
    ) throws -> Transfer? {
        // Construct URL
        let urlTemplate = "/{container}/{blob}"
        let pathParams = [
            "container": container,
            "blob": blob
        ]
        guard let url = self.url(forTemplate: urlTemplate, withKwargs: pathParams) else { return nil }
        guard let context = StorageBlobClient.manager.persistentContainer?.viewContext else { return nil }
        let start = Int64(options?.range?.offset ?? 0)
        let end = Int64(options?.range?.length ?? 0)
        let downloader = try BlobStreamDownloader(
            client: self,
            source: url,
            destination: destinationUrl,
            options: options
        )
        let blobTransfer = BlobTransfer.with(
            context: context,
            clientRestorationId: restorationId,
            source: url,
            destination: destinationUrl,
            type: .download,
            startRange: start,
            endRange: end,
            parent: nil
        )
        blobTransfer.downloader = downloader
        blobTransfer.downloadOptions = options ?? DownloadBlobOptions()
        StorageBlobClient.manager.add(transfer: blobTransfer)
        return blobTransfer
    }

    /// Reliably upload a blob to a storage container.
    ///
    /// This method will reliably manage the transfer of the blob from this device to the cloud service. When called,
    /// a transfer will be queued and a `Transfer` object will be returned that provides a handle to the transfer. This
    /// client's `transferDelegate` will be notified about state changes for all transfers managed by the client.
    /// - Parameters:
    ///   - sourceUrl: The URL to a file on this device.
    ///   - container: The name of the container.
    ///   - blob: The name of the blob.
    ///   - properties: Properties to set on the resulting blob.
    ///   - options: An `UploadBlobOptions` object to control the upload operation.
    public func upload(
        file sourceUrl: URL,
        toContainer container: String,
        asBlob blob: String,
        properties: BlobProperties,
        withOptions options: UploadBlobOptions? = nil
    ) throws -> Transfer? {
        // Construct URL
        let urlTemplate = "/{container}/{blob}"
        let pathParams = [
            "container": container,
            "blob": blob
        ]
        guard let url = self.url(forTemplate: urlTemplate, withKwargs: pathParams) else { return nil }
        guard let context = StorageBlobClient.manager.persistentContainer?.viewContext else { return nil }
        let uploader = try BlobStreamUploader(
            client: self,
            source: sourceUrl,
            destination: url,
            properties: properties,
            options: options
        )
        let blobTransfer = BlobTransfer.with(
            context: context,
            clientRestorationId: restorationId,
            source: sourceUrl,
            destination: url,
            type: .upload,
            startRange: 0,
            endRange: Int64(uploader.fileSize),
            parent: nil
        )
        blobTransfer.uploader = uploader
        blobTransfer.uploadOptions = options ?? UploadBlobOptions()
        blobTransfer.properties = properties
        StorageBlobClient.manager.add(transfer: blobTransfer)
        return blobTransfer
    }

    // MARK: PathHelper

    /// Helper containing properties and values to aid in constructing local paths for working with blobs.
    public struct PathHelper {
        /// The application's temporary directory.
        public static let tempDir = URL(string: tempDirPrefix)!
        private static let tempDirPrefix = "tempDir:/"
        private static let realTempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        /// The application's cache directory.
        public static let cacheDir = URL(string: cacheDirPrefix)!
        private static let cacheDirPrefix = "cacheDir:/"
        private static let realCacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!

        /// The application's documents directory.
        public static let documentsDir = URL(string: documentsDirPrefix)!
        private static let documentsDirPrefix = "documentsDir:/"
        private static let realDocumentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!

        internal static func absoluteUrl(forStorageRelativeUrl url: URL) -> URL? {
            var urlString = url.absoluteString
            if urlString.starts(with: cacheDirPrefix) {
                urlString = urlString.replacing(prefix: cacheDirPrefix, with: realCacheDir.absoluteString)
                return URL(string: urlString)
            } else if urlString.starts(with: tempDirPrefix) {
                urlString = urlString.replacing(prefix: tempDirPrefix, with: realTempDir.absoluteString)
                return URL(string: urlString)
            } else if urlString.starts(with: documentsDirPrefix) {
                urlString = urlString.replacing(prefix: documentsDirPrefix, with: realDocumentsDir.absoluteString)
                return URL(string: urlString)
            }
            return url
        }

        /// Retrieve a URL for a location on the local device in which to store a blob downloaded from a container.
        /// - Parameters:
        ///   - directoryUrl: The base directory to construct the path within. The default is the application's cache
        ///     directory.
        ///   - name: The name of the blob.
        ///   - container: The name of the container.
        public static func localUrl(
            inDirectory directoryUrl: URL = cacheDir,
            forBlob name: String,
            inContainer container: String
        ) -> URL {
            let (dirName, fileName) = pathComponents(forBlob: name, inContainer: container)
            return directoryUrl.appendingPathComponent(dirName).appendingPathComponent(fileName)
        }

        /// Retrieve the directory and filename components for a blob within a container. Returns a tuple of (`dirName`,
        /// `fileName`), where `dirName` is the string up to, but not including, the final '/', and `fileName` is the
        /// component following the final '/'.
        /// - Parameters:
        ///   - name: The name of the blob.
        ///   - container: The name of the container
        /// - Returns: A tuple of (`dirName`, `fileName`)
        public static func pathComponents(
            forBlob name: String,
            inContainer container: String
        ) -> (dirName: String, fileName: String) {
            var defaultUrlComps = "\(container)/\(name)".split(separator: "/").compactMap { String($0) }
            let baseName = defaultUrlComps.popLast()!
            let dirName = defaultUrlComps.joined(separator: "/")
            return (dirName, baseName)
        }
    }
}

// MARK: Paged Collection Delegate

extension StorageBlobClient: PagedCollectionDelegate {
    /// :nodoc:
    public func continuationUrl(
        continuationToken: String,
        queryParams: inout [QueryParameter],
        requestUrl: URL
    ) -> URL? {
        queryParams.append("marker", continuationToken)
        return requestUrl
    }
}

// MARK: Transfer Delegate

extension StorageBlobClient: TransferDelegate {
    /// :nodoc:
    public func transfer(
        _ transfer: Transfer,
        didUpdateWithState state: TransferState,
        andProgress progress: Float?
    ) {
        transferDelegate?.transfer(transfer, didUpdateWithState: state, andProgress: progress)
    }

    /// :nodoc:
    public func transfer(_ transfer: Transfer, didFailWithError error: Error) {
        transferDelegate?.transfer(transfer, didFailWithError: error)
    }

    /// :nodoc:
    public func transferDidComplete(_ transfer: Transfer) {
        transferDelegate?.transferDidComplete(transfer)
    }

    /// :nodoc:
    public func client(forRestorationId restorationId: String) -> PipelineClient? {
        transferDelegate?.client(forRestorationId: restorationId)
    }
}

// MARK: Transfer Manager Methods

extension StorageBlobClient {
    /// Start the transfer management engine.
    ///
    /// Loads transfer state from disk, begins listening for network connectivity events, and resumes any incomplete
    /// transfers. This method **MUST** be called by your application in order for any managed transfers to occur.
    /// It's recommended to call this method from a background thread, at an opportune time after your app has started.
    ///
    /// Note that depending on the type of credential used by this `StorageBlobClient`, resuming transfers may cause a
    /// login UI to be displayed if the token for a paused transfer has expired. Because of this, it's not recommended
    /// to call this method from your `AppDelegate`. If you're using such a credential (e.g. `MSALCredential`) you
    /// should first inspect the list of transfers to determine if any are pending. If so, you should assume that
    /// calling this method may display a login UI, and call it in a user-appropriate context (e.g. display a "pending
    /// transfers" message and wait for explicit user confirmation to start the management engine). If you're not using
    /// such a credential, or there are no paused transfers, it is safe to call this method from your `AppDelegate`.
    public func startManaging() {
        StorageBlobClient.manager.startManaging()
    }

    /// Stop the transfer management engine.
    ///
    /// Pauses all incomplete transfers, stops listening for network connectivity events, and stores transfer state to
    /// disk. This method **SHOULD** be called by your application, either from your `AppDelegate` or from within a
    /// `ViewController`'s lifecycle methods.
    public func stopManaging() {
        StorageBlobClient.manager.stopManaging()
    }

    /// Cancel all currently active transfers having this client's `restorationId`.
    public func cancelAllTransfers() {
        StorageBlobClient.manager.cancelAll(withRestorationId: restorationId)
    }

    /// Remove all transfers having this client's `restorationId` from the database. All currently active transfers will
    /// be cancelled.
    public func removeAllTransfers() {
        StorageBlobClient.manager.removeAll(withRestorationId: restorationId)
    }

    /// Pause all currently active transfers having this client's `restorationId`.
    public func pauseAllTransfers() {
        StorageBlobClient.manager.pauseAll(withRestorationId: restorationId)
    }

    /// Resume all currently paused transfers having this client's `restorationId`.
    public func resumeAllTransfers() {
        StorageBlobClient.manager.resumeAll(withRestorationId: restorationId)
    }

    /// Retrieve the list of all managed transfers having this client's `restorationId`.
    public var transfers: [Transfer] {
        return StorageBlobClient.manager.transfers.filter { $0.clientRestorationId == restorationId }
    }
}