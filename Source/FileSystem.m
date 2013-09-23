/*
    FileSystem.m
    MobileBackupMounter
    (c) 2013 Ricci Adams
    MIT license, http://www.opensource.org/licenses/mit-license.php
*/


#import "FileSystem.h"
#import "MobileBackup.h"

#define ERR(X) { *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:X userInfo:nil]; return NO; }


@implementation FileSystem {
    MobileBackup *_backup;


    GMUserFileSystem *_fs;
}

- (id) initWithPath:(NSString *)path
{
    if ((self = [super init])) {
        _backup = [[MobileBackup alloc] initWithPath:path];
    }

    return self;
}



#pragma mark - Private Methods

- (MobileBackupKey *) _keyForPath:(NSString *)inPath
{
    if ([inPath hasPrefix:@"/Applications/"]) {
        inPath = [inPath stringByReplacingOccurrencesOfString:@"/Applications/" withString:@"/AppDomain-"];
    }

    NSArray *components = [inPath pathComponents];
    NSUInteger count = [components count];

    NSString *keyDomain;
    NSString *keyPath;

    if (count == 2) {
        keyDomain = [components objectAtIndex:1];

    } else if (count >= 3) {
        keyDomain = [components objectAtIndex:1];
        keyPath   = [[components subarrayWithRange:NSMakeRange(2, count - 2)] componentsJoinedByString:@"/"];
    }


    return [[MobileBackupKey alloc] initWithDomain:keyDomain path:keyPath];
}


- (NSString *) _pathForKey:(MobileBackupKey *)key
{
    NSString *domain = [key domain];
    NSString *path   = [key path];
    
    if ([domain hasPrefix:@"AppDomain-"]) {
        domain = [domain stringByReplacingOccurrencesOfString:@"AppDomain-" withString:@"Applications/"];
    }

    return [domain stringByAppendingPathComponent:path];
}


- (MobileBackupEntry *) _entryForPath:(NSString *)path
{
    MobileBackupKey *key = [self _keyForPath:path];
    return [[_backup manifest] entryWithKey:key];
}


- (void) _applyAttributes:(NSDictionary *)attributes toEntry:(MobileBackupEntry *)entry
{
    NSNumber *permissionsNumber = [attributes objectForKey:NSFilePosixPermissions];
    NSNumber *fileLengthNumber  = [attributes objectForKey:NSFileSize];
    NSNumber *userIDNumber      = [attributes objectForKey:NSFileOwnerAccountID];
    NSNumber *groupIDNumber     = [attributes objectForKey:NSFileGroupOwnerAccountID];
    NSDate   *modifiedDate      = [attributes objectForKey:NSFileModificationDate];
    NSDate   *createdDate       = [attributes objectForKey:NSFileCreationDate];

    if (fileLengthNumber) {
        [entry setFileLength:[fileLengthNumber unsignedIntegerValue]];
    }

    if (userIDNumber) {
        [entry setUserID:[userIDNumber unsignedIntValue]];
    }
    
    if (groupIDNumber) {
        [entry setGroupID:[groupIDNumber unsignedIntValue]];
    }
    
    if (modifiedDate) {
        [entry setLastModifiedTime:[modifiedDate timeIntervalSince1970]];
    }

    if (createdDate) {
        [entry setCreatedTime:[createdDate timeIntervalSince1970]];
    }
    
    if (permissionsNumber) {
        UInt32 permissions = [permissionsNumber unsignedIntValue];
        mode_t mode = ([entry mode] & ~0777) | permissions;
        [entry setMode:mode];
    }
}

#pragma mark - Directory Contents

- (NSArray *) contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error
{
    MobileBackupKey *key = [self _keyForPath:path];
    
    if (![key domain]) {
        return @[
            @"Applications",

            @"BooksDomain",
            @"CameraRollDomain",
            @"DatabaseDomain",
            @"HomeDomain",
            @"KeychainDomain",
            @"ManagedPreferencesDomain",
            @"MediaDomain",
            @"MobileDeviceDomain",
            @"RootDomain",
            @"SystemPreferencesDomain",
            @"TonesDomain",
            @"WirelessDomain",
        ];

    } else if ([[key domain] isEqualToString:@"Applications"] && ![key path]) {
        return [_backup installedApplications];

    } else {
        return [[_backup manifest] contentsOfDirectoryWithKey:key];
    }
}


#pragma mark - Getting and Setting Attributes

- (NSDictionary *) attributesOfItemAtPath:(NSString *)path userData:(id)userData error:(NSError **)error
{
    MobileBackupKey *key = [self _keyForPath:path];

    if (![key path]) {
        return  @{
            NSFileType: NSFileTypeDirectory
        };

    // File in domain
    } else {
        MobileBackupEntry *entry = [[_backup manifest] entryWithKey:key];
        
        if (entry) {
            UInt16 mode = [entry mode];
            NSString *fileType = NSFileTypeUnknown;
            UInt64 fileSize = [entry fileLength];
            mode_t posixPermissions = mode & 0777;

            NSDate *modificationDate = [NSDate dateWithTimeIntervalSince1970:[entry lastModifiedTime]];
            NSDate *creationDate = [NSDate dateWithTimeIntervalSince1970:[entry createdTime]];

            if (mode & S_IFREG) {
                fileType = NSFileTypeRegular;
            } else if (mode & S_IFCHR) {
                fileType = NSFileTypeCharacterSpecial;
            } else if (mode & S_IFDIR) {
                fileType = NSFileTypeDirectory;
            } else if (mode & S_IFBLK) {
                fileType = NSFileTypeBlockSpecial;
            } else if (mode & S_IFLNK) {
                fileType = NSFileTypeSymbolicLink;
            } else if (mode & S_IFSOCK) {
                fileType = NSFileTypeSocket;
            }

            return  @{
                NSFileType: fileType,
                NSFileSize: @(fileSize),
                NSFileModificationDate: modificationDate,
                NSFileCreationDate:     creationDate,
                NSFilePosixPermissions:    @(posixPermissions),
                NSFileOwnerAccountID:      @([entry userID]),
                NSFileGroupOwnerAccountID: @([entry groupID])
            };
        }
    }

    return nil;
}


- (BOOL) setAttributes:(NSDictionary *)attributes ofItemAtPath:(NSString *)path userData:(id)userData error:(NSError **)error
{
    MobileBackupEntry *entry = [self _entryForPath:path];
    if (!entry) ERR(ENOENT);
    
    [self _applyAttributes:attributes toEntry:entry];
    [[_backup manifest] flushChanges];
    
    return YES;
}


#pragma mark - File Contents

- (NSData *) contentsAtPath:(NSString *)path
{
    return [[self _entryForPath:path] contents];
}


- (BOOL) openFileAtPath:(NSString *)path mode:(int)mode userData:(id *)userData error:(NSError **)error
{
    MobileBackupEntry *entry = [self _entryForPath:path];
    MobileBackupOpenedFile *file = [entry openWithMode:mode error:error];
    
    if (userData) *userData = file;
    
    return file != nil;
}


- (void) releaseFileAtPath:(NSString *)path userData:(id)userData
{
    [(MobileBackupOpenedFile *)userData close];
}


- (int) readFileAtPath:(NSString *)path userData:(id)userData buffer:(char *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)error
{
    return [(MobileBackupOpenedFile *)userData readIntoBuffer:buffer size:size offset:offset error:error];
}


- (int) writeFileAtPath:(NSString *)path userData:(id)userData buffer:(const char *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)error
{
    return [(MobileBackupOpenedFile *)userData writeFromBuffer:buffer size:size offset:offset error:error];
}


- (BOOL) exchangeDataOfItemAtPath:(NSString *)path1 withItemAtPath:(NSString *)path2 error:(NSError **)error
{
    MobileBackupEntry *entry1 = [self _entryForPath:path1];
    MobileBackupEntry *entry2 = [self _entryForPath:path2];
    if (!entry1 || !entry2) ERR(ENOATTR);

    NSData *data1 = [entry1 contents];
    NSData *data2 = [entry2 contents];

    [entry1 updateContents:data2];
    [entry2 updateContents:data1];

    [[_backup manifest] flushChanges];

    return YES;
}


#pragma mark - Creation

- (BOOL) createDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes error:(NSError **)error
{
    if ([self _entryForPath:path]) ERR(EEXIST);
    
    
    MobileBackupEntry *entry = [[MobileBackupEntry alloc] init];

    [entry setMode:([entry mode] | S_IFDIR)];
    
    [entry setKey:[self _keyForPath:path]];
    [self _applyAttributes:attributes toEntry:entry];

    [[_backup manifest] addEntry:entry];

    return YES;
}


- (BOOL) createFileAtPath:(NSString *)path attributes:(NSDictionary *)attributes userData:(id *)userData error:(NSError **)error
{
    if ([self _entryForPath:path]) ERR(EEXIST);

    MobileBackupEntry *entry = [[MobileBackupEntry alloc] init];
    
    [entry setMode:([entry mode] | S_IFREG)];
    
    [entry setKey:[self _keyForPath:path]];
    [self _applyAttributes:attributes toEntry:entry];

    [[_backup manifest] addEntry:entry];

    mode_t mode = [[attributes objectForKey:NSFilePosixPermissions] longValue];
    return [entry creatWithMode:mode error:error];
}


#pragma mark - Moving / Removing

- (BOOL) moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error
{
    MobileBackupEntry *entry = [self _entryForPath:fromPath];
    if (!entry) ERR(ENOENT);

    MobileBackupKey *fromKey = [self _keyForPath:fromPath];
    MobileBackupKey *toKey   = [self _keyForPath:toPath];

    if (![[fromKey domain] isEqualToString:[toKey domain]]) {
        ERR(EACCES);
    }

    [[_backup manifest] moveEntry:entry toKey:toKey];
    [[_backup manifest] flushChanges];

    return YES;
}


- (BOOL) removeItemAtPath:(NSString *)path error:(NSError **)error
{
    MobileBackupEntry *entry = [self _entryForPath:path];
    if (!entry) ERR(ENOENT);
    
    MobileBackupKey *key = [self _keyForPath:path];
    [[_backup manifest] removeEntryWithKey:key];
    [[_backup manifest] flushChanges];
     
    return YES;
}


#pragma mark - Symbolic Links

- (BOOL) createSymbolicLinkAtPath:(NSString *)path withDestinationPath:(NSString *)otherPath error:(NSError **)error
{
    if ([self _entryForPath:path]) ERR(EEXIST);

    MobileBackupEntry *entry = [[MobileBackupEntry alloc] init];
    
    [entry setMode:([entry mode] | S_IFLNK)];
    [entry setKey:[self _keyForPath:path]];
    [entry setLinkTarget:otherPath];

    [[_backup manifest] addEntry:entry];
    [[_backup manifest] flushChanges];

    return YES;
}


- (NSString *) destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error
{
    MobileBackupEntry *entry = [self _entryForPath:path];
    return [entry linkTarget];
}


#pragma mark -
#pragma mark Public Methods

- (void) mount
{
    if (_fs) return;
    _fs = [[GMUserFileSystem alloc] initWithDelegate:self isThreadSafe:YES];

    NSString *nameToTry = [_backup displayName];
    NSString *path = [NSString stringWithFormat:@"/Volumes/%@", nameToTry];

    [_fs mountAtPath:path withOptions:@[ ]];
}

- (void) unmount
{
    //!i: Implement this
}

@end
