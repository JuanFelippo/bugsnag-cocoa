//
//  BugsnagMetadata.m
//
//  Created by Conrad Irwin on 2014-10-01.
//
//  Copyright (c) 2014 Bugsnag, Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "BugsnagMetadata.h"
#import "BSGSerialization.h"
#import "BugsnagLogger.h"

@interface BugsnagMetadata ()
@property(atomic, strong) NSMutableDictionary *dictionary;
@end

@implementation BugsnagMetadata

- (id)init {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    return [self initWithDictionary:dict];
}

- (id)initWithDictionary:(NSMutableDictionary *)dict {
    if (self = [super init]) {
        self.dictionary = dict;
    }
    [self.delegate metadataChanged:self];
    return self;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    @synchronized(self) {
        NSMutableDictionary *dict = [self.dictionary mutableCopy];
        return [[BugsnagMetadata alloc] initWithDictionary:dict];
    }
}

- (NSMutableDictionary *)getTab:(NSString *)tabName {
    @synchronized(self) {
        NSMutableDictionary *tab = self.dictionary[tabName];
        if (!tab) {
            tab = [NSMutableDictionary dictionary];
            self.dictionary[tabName] = tab;
        }
        return tab;
    }
}

- (void)clearTab:(NSString *)tabName {
    bool metadataChanged = false;
    @synchronized(self) {
        if ([self.dictionary objectForKey:tabName]) {
            [self.dictionary removeObjectForKey:tabName];
            metadataChanged = true;
        }
    }

    if (metadataChanged) {
        [self.delegate metadataChanged:self];
    }
}

- (NSDictionary *)toDictionary {
    @synchronized(self) {
        return [NSDictionary dictionaryWithDictionary:self.dictionary];
    }
}

/**
 * Add a single key/value to a metadata Tab/Section.
 */
- (void)addAttribute:(NSString *)attributeName
           withValue:(id)value
       toTabWithName:(NSString *)tabName {
    
    bool metadataChanged = false;
    @synchronized(self) {
        if (value) {
            id cleanedValue = BSGSanitizeObject(value);
            if (cleanedValue) {
                [self getTab:tabName][attributeName] = cleanedValue;
                metadataChanged = true;
            } else {
                Class klass = [value class];
                bsg_log_err(@"Failed to add metadata: Value of class %@ is not "
                            @"JSON serializable",
                            klass);
            }
        } else {
            [[self getTab:tabName] removeObjectForKey:attributeName];
            metadataChanged = true;
        }
    }
    
    if (metadataChanged) {
        [self.delegate metadataChanged:self];
    }
}

/**
 * Merge supplied and existing metadata.
 */
- (void)addMetadataToSection:(NSString *)section
                      values:(NSDictionary *)values
{
    @synchronized(self) {
        if (values) {
            // Check each value in turn.  Remove nulls, add/replace others
            // Fast enumeration over the (unmodified) supplied values for simplicity
            bool metadataChanged = false;
            for (id key in values) {
                // Ensure keys are (JSON-serializable) strings
                if ([[key class] isSubclassOfClass:[NSString class]]) {
                    id value = [values objectForKey:key];
                    
                    // The common case: adding sensible values
                    if (value && value != [NSNull null]) {
                        id cleanedValue = BSGSanitizeObject(value);
                        if (cleanedValue) {
                            // We only want to create a tab if we have a valid value.
                            NSMutableDictionary *tab = [self getTab:section];
                            [tab setObject:cleanedValue forKey:key];
                            metadataChanged = true;
                        }
                        // Log the failure but carry on
                        else {
                            Class klass = [value class];
                            bsg_log_err(@"Failed to add metadata: Value of class %@ is not "
                                        @"JSON serializable.", klass);
                        }
                    }
                    
                    // Remove existing value if supplied null.
                    // Ensure we don't inadvertently create a section.
                    else if (value == [NSNull null]
                             && [self.dictionary objectForKey:section]
                             && [[self.dictionary objectForKey:section] objectForKey:key])
                    {
                        [[self.dictionary objectForKey:section] removeObjectForKey:key];
                        metadataChanged = true;
                    }
                }
                
                // Something went wrong...
                else {
                    bsg_log_err(@"Failed to update metadata: Section: %@, Values: %@", section, values);
                }
            }
            
            // Call the delegate if we've materially changed it
            if (metadataChanged) {
                [self.delegate metadataChanged:self];
            }
        }
    }
}

@end
