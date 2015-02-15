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




#import <Foundation/Foundation.h>

@protocol HWSValueConverter;

@protocol HWSValueConverterRegistry<NSObject>

- (id<HWSValueConverter>)valueConverterForTag:(NSString *)type;

@end