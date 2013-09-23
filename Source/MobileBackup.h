/*
    MobileBackup.h
    MobileBackupMounter
    (c) 2013 Ricci Adams
    MIT license, http://www.opensource.org/licenses/mit-license.php
*/


#import <Foundation/Foundation.h>

@class MobileBackupManifest;
@class MobileBackupKey;
@class MobileBackupEntry;
@class MobileBackupOpenedFile;


@interface MobileBackup : NSObject

- (id) initWithPath:(NSString *)path;

@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) MobileBackupManifest *manifest;
@property (nonatomic, readonly) NSArray *installedApplications;

@end


@interface MobileBackupManifest : NSObject

- (id) initWithPath:(NSString *)path;

@property (readonly) NSString *path;
@property (readonly) NSInteger version;

@property (readonly) NSArray *entries;

@property (readonly) NSArray *availableDomains;

- (void) addEntry:(MobileBackupEntry *)entry;
- (void) removeEntryWithKey:(MobileBackupKey *)key;
- (void) moveEntry:(MobileBackupEntry *)entry toKey:(MobileBackupKey *)key;

- (MobileBackupEntry *) entryWithKey:(MobileBackupKey *)key;

- (NSArray *) contentsOfDirectoryWithKey:(MobileBackupKey *)key;

- (void) flushChanges;

@end


@interface MobileBackupKey : NSObject <NSCopying>

- (id) initWithDomain:(NSString *)domain path:(NSString *)path;

@property (readonly) NSString *domain;
@property (readonly) NSString *path;

- (NSString *) localFilename; // sha1(domain . '-' . path)

@end


@interface MobileBackupEntry : NSObject

- (NSString *) localPathInBackup;
- (NSData *) contents;

- (MobileBackupOpenedFile *) creatWithMode:(int)mode error:(NSError **)error;
- (MobileBackupOpenedFile *) openWithMode:(int)mode error:(NSError **)outError;

- (void) updateContents:(NSData *)contents;

@property (copy) MobileBackupKey *key;

@property (copy) NSString *linkTarget;
@property (copy) NSData *hash;
@property (copy) NSData *encryptionKey;

@property (assign) mode_t mode;
@property (assign) UInt64 inode;

@property (assign) UInt32 userID;
@property (assign) UInt32 groupID;

@property (assign) time_t lastModifiedTime;
@property (assign) time_t lastAccessedTime;
@property (assign) time_t createdTime;

@property (assign) UInt64 fileLength;

@property (assign) UInt8 flag;

@property (strong) NSDictionary *properties;

- (void) setPropertyValue:(id)value forKey:(NSString *)key;
- (id) propertyValueForKey:(NSString *)key;

@end


@interface MobileBackupOpenedFile : NSObject

- (void) close;

- (ssize_t) readIntoBuffer:(char *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)error;
- (ssize_t) writeFromBuffer:(const char *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)error;

@end

