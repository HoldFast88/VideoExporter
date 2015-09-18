# VideoExporter
Allows to export video, presented as AVAsset, with CIFilter.

Is extremely easy to use! You shouls just call one of the VideoExporter's methods:

- (void)exportVideoAtURL:(NSURL *)videoURL withCIFilterName:(NSString *)filterName andCompletionHandler:(ExportCompletionHandler)completionHandler;
- (void)exportVideoAsset:(AVAsset *)videoAsset withCIFilterName:(NSString *)filterName andCompletionHandler:(ExportCompletionHandler)completionHandler;

filterName parameter is the name for CIFilter initializing:
CIFilter *filter = [CIFilter filterWithName:filterName];
