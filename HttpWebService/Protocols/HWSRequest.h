////////////////////////////////////////////////////////////////////////////////
//
//  AppsQuick.ly
//  Copyright 2015 AppsQuick.ly
//  All Rights Reserved.
//
//  NOTICE: This software is the proprietary information of AppsQuick.ly
//  Use is subject to license terms.
//
////////////////////////////////////////////////////////////////////////////////


#define ValueOrNull(value) (value?:[NSNull null])


typedef NSInteger HttpStatusCode;

typedef NS_ENUM(NSInteger, HttpRequestMethod) {
    HttpRequestMethodPost,
    HttpRequestMethodGet,
    HttpRequestMethodPut,
    HttpRequestMethodDelete,
    HttpRequestMethodPatch,
    HttpRequestMethodHead
};

typedef NS_ENUM(NSInteger, HttpRequestSerialization) {
    HttpRequestSerializationJson,
    HttpRequestSerializationHttp,
    HttpRequestSerializationPlist
};

typedef NS_ENUM(NSInteger, HttpResponseSerialization) {
    HttpResponseSerializationJson,
    HttpResponseSerializationXml,
    HttpResponseSerializationPlist,
    HttpResponseSerializationData,
    HttpResponseSerializationString,
    HttpResponseSerializationImage,
};

@protocol HWSRequest<NSObject>

//=============================================================================================================================
#pragma mark - Request
//=============================================================================================================================

@required

/**
* Provide endpoint here. It can be relative path as well as absolute path to endpoint (matching by http: or https: prefix)
*
* If your URL has dynamic parts, you can mark them as path argument via curly braces like this:
*    order/{id}
* - that means that url has one argument named 'id' and it will be replaced by real value specified in 'pathParameters'.
* @see pathParameters
* */
- (NSString *)path;

/**
* Specify one of HTTP methods type here
* */
- (HttpRequestMethod)method;

@optional

/**
* This method should return dictionary with path arguments and variables
*
* Arguments - dynamic parts of URL path, wrapped by braces.
* For example:
*    order/{id}
*    person/{person-id}/children/{child-id}
*
* Variables - usual URL parameters, like this:
*    order?id=123
*    person?person-id=123&child-id=321
*
* In both examples dictionary should be: @{ @"person-id":@"123", @"child-id": @"321" }
*
* Of course you can mix arguments and variables together in one dictionary
* For example if want to compose something like this:
*    person/123?child-id=321
* your path should be:
*    person/{person-id}
* and pathParameters should be:
*    @{ @"person-id":@"123", @"child-id": @"321" }
* */
- (NSDictionary *)pathParameters;

/**
* Provide data for the request body here.
* This data can be of type:
* - NSArray or NSDictionary - will be validated using specified schema and serialized using 'requestSerialization' type
* - NSData - will be passed as is into request body
* - NSString - will be converted into NSData using UTF-8 encoding
* - NSInputStream - mostly used to specify file for uploading
* */
- (id)requestBody;

/**
* Provide custom HTTP headers here. These headers will override default on conflicts.
* */
- (NSDictionary *)requestHeaders;

/**
* Specify name of schema file. This file must be included into application bundle.
* If this method not implement then ClassName.request name assumed
* */
- (NSString *)requestBodyValidationSchemaName;

/**
* Specify name of schema file. This file must be included into application bundle.
* If this method not implement then ClassName.url name assumed
* */
- (NSString *)requestPathParametersValidationSchemaName;

/**
* Specify kind of request to send here. Using that type NSArray or NSDictionary request body will be converted to NSData.
* If 'requestBody' is NSData, NSString or NSInputStream this method will be ignored (And warning appears in the console).
* */
- (HttpRequestSerialization)requestSerialization;

//=============================================================================================================================
#pragma mark - Response
//=============================================================================================================================

@optional
/**
* Specify name of schema file. This file must be included into application bundle.
* If this method not implement then ClassName.response name assumed
* */
- (NSString *)responseBodyValidationSchemaName;

/**
* Specify kind of expected response here. This information used to compose object from response body.
*
* Note: If want to save response body as is to file, then don't implement this method. Check responseBodyOutputStream
* method instead.
* If you implemented 'responseBodyOutputStream', then this method will be ignored!
* */
- (HttpResponseSerialization)responseSerialization;

/**
* Implement this method to specify custom output stream. If you implement this method all output will be forwarded into
* that stream and 'bodyObject' will be nil (so responseSerialization and validation will not be used). Useful when you
* want to save binary response data to disk to avoid memory overhead.
* */
- (NSOutputStream *)responseBodyOutputStream;

/**
* Result of this method will be returned as 'result' in the 'sendRequest:completion:' method of HttpWebService.
* You can implement this method to compose your own model object from NSDictionary/NSArray by parsing.
* If no implementation given, bodyObject will be used as 'result'.
*
* bodyObject represents HTTP body content depending on 'responseSerialization' value.
*
* bodyObject can be:
*  - NSArray or NSDictionary (depending on content) when responseSerialization is HttpResponseSerialization(Json/Xml/Plist)
*  - NSData when responseSerialization is HttpResponseSerializationImage
*  - UIImage when responseSerialization is HttpResponseSerializationData
*  - NSString when responseSerialization is HttpResponseSerializationString
*  - nil when responseBodyOutputStream specified (you can hold path to file based OutputStream and post-process result here)
* */
- (id)responseProcessedFromBody:(id)bodyObject headers:(NSDictionary *)responseHeaders status:(HttpStatusCode)statusCode error:(NSError **)parseError;

/**
* Error notification. Called when network call ended with error. Used to do some custom logic on error (for example delete resource at output stream, clean up, etc.. )
* */
- (void)respondedWithError:(NSError *)networkError headers:(NSDictionary *)responseHeaders status:(HttpStatusCode)statusCode;

@end
