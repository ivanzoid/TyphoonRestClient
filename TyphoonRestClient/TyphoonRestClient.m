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




#import "TyphoonRestClient.h"
#import "TRCRequest.h"
#import "TRCSchema.h"
#import "TRCUtils.h"
#import "TRCConverter.h"
#import "TRCValueConverter.h"
#import "TRCConvertersRegistry.h"
#import "TRCErrorParser.h"
#import "TRCConnection.h"
#import "TRCValueConverterUrl.h"
#import "TRCValueConverterString.h"
#import "TRCValueConverterNumber.h"
#import "TRCObjectMapper.h"

#define TRCSetError(errorPointer, error) if (errorPointer) { *errorPointer = error; }

@interface TyphoonRestClient ()<TRCConvertersRegistry>
@end

@implementation TyphoonRestClient
{
    NSMutableDictionary *_typeConverterRegistry;
    NSMutableDictionary *_objectMapperRegistry;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _typeConverterRegistry = [NSMutableDictionary new];
        _objectMapperRegistry = [NSMutableDictionary new];
        [self registerDefaultTypeConverters];
        self.defaultRequestSerialization = TRCRequestSerializationJson;
        self.defaultResponseSerialization = TRCResponseSerializationJson;
        self.validationOptions = TRCValidationOptionsTreatEmptyDictionaryAsNilInResponsesForOptional |
                TRCValidationOptionsTreatEmptyDictionaryAsNilInRequestsForOptional;
    }
    return self;
}

- (id<TRCProgressHandler>)sendRequest:(id<TRCRequest>)request completion:(void (^)(id result, NSError *error))completion
{
    NSParameterAssert(self.connection);

    NSError *requestComposingError = nil;
    NSMutableURLRequest *httpRequest = [self requestFromRequest:request error:&requestComposingError];

    if (requestComposingError) {
        if (completion) {
            completion(nil, requestComposingError);
        }
        return nil;
    }
    NSParameterAssert(httpRequest);

    NSOutputStream *output = nil;
    if ([request respondsToSelector:@selector(responseBodyOutputStream)]) {
        output = [request responseBodyOutputStream];
    }

    TRCResponseSerialization responseSerialization = self.defaultResponseSerialization;
    if ([request respondsToSelector:@selector(responseSerialization)]) {
        responseSerialization = [request responseSerialization];
        if (output && responseSerialization != TRCResponseSerializationData) {
            [self logWarning:@"Both 'responseSerialization' and 'responseBodyOutputStream' methods implemented in '%@' request. "
                                     "Value returned by 'responseSerialization' method will be ignored. To avoid this warning please remove"
                                     " 'responseSerialization' implementation or change returned value to TRCResponseSerializationData", [request class]];
        }
    }

    if (output) {
        responseSerialization = TRCResponseSerializationData;
    }

    return [self.connection sendRequest:httpRequest responseSerialization:responseSerialization outputStream:output completion:^(id responseObject, NSError *networkError, id<TRCResponseInfo> responseInfo) {
        [self handleResponse:responseObject withError:networkError info:responseInfo forRequest:request completion:^(id result, NSError *error) {
            if (completion) {
                completion(result, error);
            }
        }];
    }];
}

//-------------------------------------------------------------------------------------------
#pragma mark - Request composing
//-------------------------------------------------------------------------------------------

- (NSMutableURLRequest *)requestFromRequest:(id<TRCRequest>)request error:(NSError **)error
{
    NSError *composingError = nil;

    id body = [self requestBodyFromRequest:request error:&composingError];

    if (composingError) {
        TRCSetError(error, composingError);
        return nil;
    }

    TRCRequestSerialization serialization = [self requestSerializationFromRequest:request body:body];

    NSMutableDictionary *pathParams = [[self requestPathParametersFromRequest:request error:&composingError] mutableCopy];

    if (composingError) {
        TRCSetError(error, composingError);
        return nil;
    }

    NSDictionary *customHeaders = nil;
    if ([request respondsToSelector:@selector(requestHeaders)]) {
        customHeaders = [request requestHeaders];
    }


    NSString *path = [self requestPathFromRequest:request params:pathParams error:&composingError];
    if (composingError) {
        TRCSetError(error, composingError);
        return nil;
    }

    NSMutableURLRequest *result = [self.connection requestWithMethod:[request method] path:path pathParams:pathParams body:body serialization:serialization headers:customHeaders error:&composingError];
    if (composingError) {
        TRCSetError(error, composingError)
        return nil;
    }
    return result;
}

- (id)requestBodyFromRequest:(<TRCRequest>)request error:(NSError **)error
{
    id body = nil;
    if ([request respondsToSelector:@selector(requestBody)]) {
        body = [request requestBody];
        if ([body isKindOfClass:[NSArray class]] || [body isKindOfClass:[NSDictionary class]]) {
            NSError *validationOrConversionError = nil;
            TRCSchema *schema = [self schemeForRequest:request];
            body = [self convertThenValidateObject:body withScheme:schema error:&validationOrConversionError];
            if (validationOrConversionError) {
                TRCSetError(error, validationOrConversionError);
                return nil;
            }
        }
    }
    return body;
}

- (TRCRequestSerialization)requestSerializationFromRequest:(<TRCRequest>)request body:(id)body
{
    TRCRequestSerialization serialization = self.defaultRequestSerialization;
    if ([request respondsToSelector:@selector(requestSerialization)]) {
        serialization = [request requestSerialization];
        if (![body isKindOfClass:[NSArray class]] && ![body isKindOfClass:[NSDictionary class]]) {
            [self logWarning:@"Body object of type '%@' can't be serialized, but you implemented 'requestSerialization' method in %@ request. Specified serialization will be ignored.", [body class], [request class]];
        }
    }
    return serialization;
}

- (NSDictionary *)requestPathParametersFromRequest:(<TRCRequest>)request error:(NSError **)error
{
    NSDictionary *pathParams = nil;
    if ([request respondsToSelector:@selector(pathParameters)]) {
        pathParams = [request pathParameters];
        NSError *validationOrConversionError = nil;
        TRCSchema *schema = [self schemeForPathParametersWithRequest:request];
        pathParams = [self convertThenValidateObject:pathParams withScheme:schema error:&validationOrConversionError];
        if (validationOrConversionError) {
            TRCSetError(error, validationOrConversionError);
            return nil;
        }
    }
    return pathParams;
}

- (NSString *)requestPathFromRequest:(<TRCRequest>)request params:(NSMutableDictionary *)params error:(NSError **)error
{
    NSString *path = [request path];
    if (path && params.count > 0) {
        NSError *argumentsApplyingError = nil;
        path = TRCUrlPathFromPathByApplyingArguments(path, params, &argumentsApplyingError);
        if (argumentsApplyingError) {
            TRCSetError(error, argumentsApplyingError);
            return nil;
        }
    }
    return path;
}
//-------------------------------------------------------------------------------------------
#pragma mark - Response handling
//-------------------------------------------------------------------------------------------

- (void)handleResponse:(id)responseObject withError:(NSError *)error info:(id<TRCResponseInfo>)responseInfo forRequest:(id<TRCRequest>)request completion:(void (^)(id result, NSError *error))completion
{
    NSParameterAssert(completion);
    if (error) {
        //Parse response for error description if needed:
        error = [self errorFromNetworkError:error withResponse:responseObject request:request responseInfo:responseInfo];

        //Notify request with error
        if ([request respondsToSelector:@selector(respondedWithError:headers:status:)]) {
            [request respondedWithError:error headers:[responseInfo.response allHeaderFields] status:[responseInfo.response statusCode]];
        }

        completion(nil, error);
        return;
    }

    TRCSchema *scheme = [self schemeForResponseWithRequest:request];

    NSError *validationOrConversionError = nil;
    id converted = [self validateThenConvertObject:responseObject withScheme:scheme error:&validationOrConversionError];

    if (validationOrConversionError) {
        completion(nil, validationOrConversionError);
    } else {
        [self parseResponse:converted withRequest:request responseInfo:responseInfo withCompletion:completion];
    }
}

- (void)parseResponse:(id)response withRequest:(id<TRCRequest>)request responseInfo:(id<TRCResponseInfo>)responseInfo withCompletion:(void (^)(id result, NSError *error))completion
{
    id result = response;

    NSError *parsingError = nil;

    if ([request respondsToSelector:@selector(responseProcessedFromBody:headers:status:error:)]) {
        result = [request responseProcessedFromBody:response headers:responseInfo.response.allHeaderFields status:responseInfo.response.statusCode error:&parsingError];
    }

    if (parsingError) {
        completion(nil, parsingError);
    } else {
        completion(result, nil);
    }
}

- (id)validateThenConvertObject:(id)object withScheme:(TRCSchema *)scheme error:(NSError **)error
{
    BOOL isObjectCanBeValidated = [object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSDictionary class]];
    if (!isObjectCanBeValidated) {
        if (scheme && object) {
            [self logWarning:@"Object of type '%@' can't be validated, but validation scheme '%@' specified. Validation scheme ignored", [object class], scheme.name];
        }
        return object;
    }

    //Scheme validation
    NSError *validationError = nil;
    if (![self validateResponse:object withSchema:scheme error:&validationError]) {
        if (!validationError) {
            validationError = TRCUnknownValidationErrorForObject(object, [scheme name], YES);
        }

        if (validationError && error) {
            *error = validationError;
        }
        return object;
    }

    //Values conversion
    NSError *convertError = nil;
    id converted = [self convertValuesInResponse:object schema:scheme error:&convertError];
    if (convertError && error) {
        *error = convertError;
    }
    return converted;
}

- (id)convertThenValidateObject:(id)object withScheme:(TRCSchema *)scheme error:(NSError **)error
{
    BOOL isObjectCanBeValidated = [object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSDictionary class]];
    if (!isObjectCanBeValidated) {
        if (scheme && object) {
            [self logWarning:@"Object of type '%@' can't be validated, but validation scheme '%@' specified. Validation scheme ignored", [object class], scheme.name];
        }
        return object;
    }

    //Values conversion
    NSError *convertError = nil;
    id converted = [self convertValuesInRequest:object schema:scheme error:&convertError];
    if (convertError && error) {
        *error = convertError;
    }
    if (convertError) {
        return converted;
    }

    //Scheme validation
    NSError *validationError = nil;
    if (![self validateRequest:converted withSchema:scheme error:&validationError]) {
        if (!validationError) {
            validationError = TRCUnknownValidationErrorForObject(converted, [scheme name], NO);
        }
        if (validationError && error) {
            *error = validationError;
        }
    }

    return converted;
}

- (NSError *)errorFromNetworkError:(NSError *)networkError withResponse:(id)response request:(id<TRCRequest>)request responseInfo:(id<TRCResponseInfo>)info
{
    NSError *result = networkError;

    if (self.errorParser && response) {
        TRCSchema *scheme = [self schemeForErrorParser:self.errorParser];
        NSError *convertError = nil;
        id converted = [self validateThenConvertObject:response withScheme:scheme error:&convertError];

        if (convertError) {
            [self logWarning:@"Error schema validation/conversion error: \"%@\". Will return ordinary network error", convertError.localizedDescription];
        } else {
            NSError *error = nil;
            NSError *parsedError = [self.errorParser errorFromResponseBody:converted headers:info.response.allHeaderFields status:info.response.statusCode error:&error];

            if (error) {
                [self logWarning:@"Error parsing error: \"%@\". Will return ordinary network error", error.localizedDescription];
            } else {
                result = parsedError;
            }
        }
    }

    return result;
}

//-------------------------------------------------------------------------------------------
#pragma mark - Validation
//-------------------------------------------------------------------------------------------

- (BOOL)validateResponse:(id)response withSchema:(TRCSchema *)schema error:(NSError **)error
{
    if (!response || !schema) {
        return YES;
    }

    return [schema validateResponse:response error:error];
}

- (BOOL)validateRequest:(id)request withSchema:(TRCSchema *)schema error:(NSError **)error
{
    if (!request || !schema) {
        return YES;
    }

    return [schema validateRequest:request error:error];
}

//-------------------------------------------------------------------------------------------
#pragma mark - Conversion
//-------------------------------------------------------------------------------------------

- (id)convertValuesInResponse:(id)arrayOrDictionary schema:(TRCSchema *)scheme error:(NSError **)parseError
{
    if (!scheme) {
        return arrayOrDictionary;
    }

    TRCConverter *converter = [[TRCConverter alloc] initWithResponseValue:arrayOrDictionary schemaValue:[scheme schemeArrayOrDictionary] schemaName:[scheme name]];
    converter.registry = self;
    converter.options = self.validationOptions;
    id result = [converter convertValues];
    NSError *error = [converter conversionError];
    if (error && parseError) {
        *parseError = error;
    }

    return result;
}

- (id)convertValuesInRequest:(id)arrayOrDictionary schema:(TRCSchema *)scheme error:(NSError **)parseError
{
    if (!scheme) {
        return arrayOrDictionary;
    }

    TRCConverter *converter = [[TRCConverter alloc] initWithRequestValue:arrayOrDictionary schemaValue:[scheme schemeArrayOrDictionary] schemaName:[scheme name]];
    converter.registry = self;
    converter.options = self.validationOptions;
    id result = [converter convertValues];
    NSError *error = [converter conversionError];
    if (error && parseError) {
        *parseError = error;
    }

    return result;
}

//-------------------------------------------------------------------------------------------
#pragma mark - Scheme fetches
//-------------------------------------------------------------------------------------------

- (TRCSchema *)requestSchemaForMapperWithTag:(NSString *)tag
{
    id<TRCObjectMapper>mapper = [self objectMapperForTag:tag];
    if (!mapper) {
        return nil;
    } else {
        NSString *name = NSStringFromClass([mapper class]);

        if ([mapper respondsToSelector:@selector(requestValidationSchemaName)]) {
            name = [mapper requestValidationSchemaName];
        }

        return [self schemeWithName:name extensionsToTry:@[@"request", @"json", @"schema"]];
    }
}

- (TRCSchema *)responseSchemaForMapperWithTag:(NSString *)tag
{
    id<TRCObjectMapper>mapper = [self objectMapperForTag:tag];
    if (!mapper) {
        return nil;
    } else {
        NSString *name = NSStringFromClass([mapper class]);

        if ([mapper respondsToSelector:@selector(responseValidationSchemaName)]) {
            name = [mapper responseValidationSchemaName];
        }

        return [self schemeWithName:name extensionsToTry:@[@"response", @"json", @"schema"]];
    }
}

- (TRCSchema *)schemeForErrorParser:(id<TRCErrorParser>)parser
{
    NSString *schemaName = NSStringFromClass([parser class]);

    if ([parser respondsToSelector:@selector(errorValidationSchemaName)]) {
        schemaName = [parser errorValidationSchemaName];
    }

    return [self schemeWithName:schemaName extensionsToTry:nil];
}

- (TRCSchema *)schemeForResponseWithRequest:(id<TRCRequest>)request
{
    NSString *schemaName = [NSStringFromClass([request class]) stringByAppendingPathExtension:@"response"];

    if ([request respondsToSelector:@selector(responseBodyValidationSchemaName)]) {
       schemaName = [request responseBodyValidationSchemaName];
    }

    return [self schemeWithName:schemaName extensionsToTry:nil];
}

- (TRCSchema *)schemeForPathParametersWithRequest:(id<TRCRequest>)request
{
    NSString *schemaName = [NSStringFromClass([request class]) stringByAppendingPathExtension:@"url"];

    if ([request respondsToSelector:@selector(requestPathParametersValidationSchemaName)]) {
        schemaName = [request requestPathParametersValidationSchemaName];
    }
    return [self schemeWithName:schemaName extensionsToTry:nil];
}

- (TRCSchema *)schemeForRequest:(id<TRCRequest>)request
{
    NSString *schemaName = [NSStringFromClass([request class]) stringByAppendingPathExtension:@"request"];

    if ([request respondsToSelector:@selector(requestBodyValidationSchemaName)]) {
        schemaName = [request requestBodyValidationSchemaName];
    }
    return [self schemeWithName:schemaName extensionsToTry:nil];
}

- (TRCSchema *)schemeWithName:(NSString *)name extensionsToTry:(NSArray *)extensions
{
    TRCSchema *scheme = [TRCSchema schemaWithName:name extensionsToTry:extensions];
    scheme.converterRegistry = self;
    scheme.options = self.validationOptions;
    return scheme;
}

//-------------------------------------------------------------------------------------------
#pragma mark - Value converters
//-------------------------------------------------------------------------------------------

- (void)registerDefaultTypeConverters
{
    [self registerValueConverter:[TRCValueConverterUrl new] forTag:@"{url}"];
    [self registerValueConverter:[TRCValueConverterString new] forTag:@"{string}"];
    [self registerValueConverter:[TRCValueConverterNumber new] forTag:@"{number}"];
}

- (void)registerValueConverter:(id<TRCValueConverter>)valueConverter forTag:(NSString *)tag
{
    NSParameterAssert(tag);
    NSAssert(_objectMapperRegistry[tag] == nil, @"This tag already used as ObjectMapper");
    if (valueConverter) {
        _typeConverterRegistry[tag] = valueConverter;
    } else {
        [_typeConverterRegistry removeObjectForKey:tag];
    }
}

//-------------------------------------------------------------------------------------------
#pragma mark - Object Mappers
//-------------------------------------------------------------------------------------------

- (void)registerObjectMapper:(id<TRCObjectMapper>)objectConverter forTag:(NSString *)tag
{
    NSParameterAssert(tag);
    NSAssert(_typeConverterRegistry[tag] == nil, @"This tag already used as ValueConverter");
    if (objectConverter) {
        _objectMapperRegistry[tag] = objectConverter;
    } else {
        [_objectMapperRegistry removeObjectForKey:tag];
    }
}

- (id<TRCObjectMapper>)objectMapperForTag:(NSString *)tag
{
    return _objectMapperRegistry[tag];
}

- (id<TRCValueConverter>)valueConverterForTag:(NSString *)tag
{
    return _typeConverterRegistry[tag];
}

//-------------------------------------------------------------------------------------------
#pragma mark - Warnings
//-------------------------------------------------------------------------------------------

- (void)logWarning:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2)
{
    if (!self.shouldSuppressWarnings) {
        va_list args;
        va_start(args, format);
        NSString *warningString = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSLog(@"TyphoonRestClient Warning: %@",warningString);
    }
}

@end