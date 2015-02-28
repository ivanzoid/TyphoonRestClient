//
//  TRCTestableObjectConverter.m
//  TyphoonRestClient
//
//  Created by Aleksey Garbarev on 17.02.15.
//  Copyright (c) 2015 Apps Quickly. All rights reserved.
//

#import "TRCModelObjectMapper.h"
#import "TestModelObject.h"
#import "TRCUtils.h"

@implementation TRCModelObjectMapper

- (BOOL)respondsToSelector:(SEL)aSelector
{
    if (aSelector == @selector(objectFromDictionary:error:)) {
        return self.responseParsingImplemented;
    } else if (aSelector == @selector(dictionaryFromObject:error:)) {
        return self.requestParsingImplemented;
    }
    return [super respondsToSelector:aSelector];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.requestParsingImplemented = YES;
        self.responseParsingImplemented=  YES;
    }
    return self;
}

- (id)objectFromDictionary:(NSDictionary *)dictionary error:(NSError **)error
{
    if ([dictionary[@"first_name"] length] < 2) {
        if (error) {
            *error = NSErrorWithFormat(@"first name can't be less than 2 symbols");
        }
        return nil;
    }

    TestModelObject *object = [TestModelObject new];
    object.firstName = dictionary[@"first_name"];
    object.lastName = dictionary[@"last_name"];
    object.avatarUrl = dictionary[@"avatar_url"];
    return object;
}

- (NSDictionary *)dictionaryFromObject:(TestModelObject *)object error:(NSError **)error
{
    if ([object.firstName length] < 2) {
        if (error) {
            *error = NSErrorWithFormat(@"first name can't be less than 2 symbols");
        }
        return nil;
    }

    NSMutableDictionary *dictionary = [NSMutableDictionary new];
    dictionary[@"first_name"] = object.firstName;
    dictionary[@"last_name"] = object.lastName;
    dictionary[@"avatar_url"] = object.avatarUrl;
    return dictionary;
}

@end