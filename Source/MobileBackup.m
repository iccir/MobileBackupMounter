/*
    MobileBackup.m
    MobileBackupMounter
    (c) 2013 Ricci Adams
    MIT license, http://www.opensource.org/licenses/mit-license.php
*/

#import "MobileBackup.h"
#import "Utils.h"


@interface MobileBackupEntry ()
- (id) _initWithReader:(DataReader *)reader;

- (void) _writeToWriter:(DataWriter *)writer;
- (void) _updateHashAndLength;

@property (nonatomic, weak) MobileBackupManifest *parentManifest;
@end


@interface MobileBackupOpenedFile ()
- (id) _initWithFileDescriptor:(int)fd;
@property (nonatomic, weak) MobileBackupEntry *parentEntry;
@end

static NSString *sGetKey(NSString *domain, NSString *path)
{
    if (!path) return domain;
    return [NSString stringWithFormat:@"%@-%@", domain, path];
}



@implementation MobileBackup {
    NSString *_path;
    NSDictionary *_info;
    NSDictionary *_status;
    MobileBackupManifest *_manifest;
}

- (id) initWithPath:(NSString *)path
{
    if ((self = [super init])) {
        _path = path;
        
        NSString *statusPath = [_path stringByAppendingPathComponent:@"Status.plist"];
        _status = [[NSDictionary alloc] initWithContentsOfFile:statusPath];

        NSString *infoPath = [_path stringByAppendingPathComponent:@"Info.plist"];
        _info = [[NSDictionary alloc] initWithContentsOfFile:infoPath];
    }

    return self;
}


- (NSString *) displayName
{
    return [_info objectForKey:@"Display Name"];
}

- (NSArray *) installedApplications
{
    return [_info objectForKey:@"Installed Applications"];
}


- (MobileBackupManifest *) manifest
{
    if (!_manifest) {
        NSString *manifestPath = [_path stringByAppendingPathComponent:@"Manifest.mbdb"];
        _manifest = [[MobileBackupManifest alloc] initWithPath:manifestPath];
    }

    return _manifest;
}


@end


@implementation MobileBackupManifest {
    NSMutableDictionary *_entryMap;
    NSMutableDictionary *_directoryMap;
    NSMutableSet *_domains;
    NSMutableArray *_entries;
}

- (id) initWithPath:(NSString *)path
{
    if ((self = [super init])) {
        _entryMap     = [NSMutableDictionary dictionary];
        _directoryMap = [NSMutableDictionary dictionary];
        _entries  = [NSMutableArray array];
    
        _path = [path copy];

        BOOL ok = [self _readFile];
        if (!ok) self = nil;
    }

    return self;
}


- (BOOL) _readFile
{
    NSData *data = [NSData dataWithContentsOfFile:_path];
    
    DataReader *reader = DataReaderCreate(data);


    UInt8 b0 = DataReaderReadUInt8(reader);
    UInt8 b1 = DataReaderReadUInt8(reader);
    UInt8 b2 = DataReaderReadUInt8(reader);
    UInt8 b3 = DataReaderReadUInt8(reader);
    UInt8 b4 = DataReaderReadUInt8(reader);
    UInt8 b5 = DataReaderReadUInt8(reader);

    if (b0 != 'm' ||
        b1 != 'b' ||
        b2 != 'd' ||
        b3 != 'b' ||
        b4 != 5   ||
        b5 != 0)
    {
        return NO;
    }
    
    _version = b4;

    _domains = [NSMutableSet set];

    while (DataReaderHasBytesAvailable(reader)) {
        MobileBackupEntry *entry = [[MobileBackupEntry alloc] _initWithReader:reader];
        
        if (DataReaderIsValid(reader)) {
            [_domains addObject:[[entry key] domain]];
            [entry setParentManifest:self];
            [self addEntry:entry];
        }
    }
    
    DataReaderFree(reader);

    return DataReaderIsValid(reader);
}


- (NSArray *) availableDomains
{
    return [_domains allObjects];
}


- (void) _addKeyToDirectoryMap:(MobileBackupKey *)inKey
{
    NSString *domain = [inKey domain];
    NSString *path   = [inKey path];

    while ([path length]) {
        NSString *parentPath = [path stringByDeletingLastPathComponent];
        NSString *filename   = [path lastPathComponent];

        if (![parentPath length]) parentPath = nil;
        MobileBackupKey *parentKey = [[MobileBackupKey alloc] initWithDomain:domain path:parentPath];
       
        NSMutableSet *directory = [_directoryMap objectForKey:parentKey];
        if (!directory) {
            directory = [NSMutableSet set];
            [_directoryMap setObject:directory forKey:parentKey];
        }

        [directory addObject:filename];

        path = parentPath;
    }
}


- (void) _removeKeyFromDirectoryMap:(MobileBackupKey *)inKey
{
    NSString *domain = [inKey domain];
    NSString *path   = [inKey path];

    NSString *parentPath = [path stringByDeletingLastPathComponent];
    NSString *filename   = [path lastPathComponent];

    if (![parentPath length]) parentPath = nil;
    MobileBackupKey *parentKey = [[MobileBackupKey alloc] initWithDomain:domain path:parentPath];
    
    NSMutableSet *directory = [_directoryMap objectForKey:parentKey];
    [directory removeObject:filename];
}


- (void) addEntry:(MobileBackupEntry *)entry
{
    MobileBackupKey   *key = [entry key];
    
    [self _addKeyToDirectoryMap:key];
    
    [_entryMap setObject:entry forKey:key];
}


- (void) removeEntryWithKey:(MobileBackupKey *)key
{
    if (!key) return;
    [self _removeKeyFromDirectoryMap:key];

    MobileBackupEntry *entry = [self entryWithKey:key];
    if (entry) [_entries removeObject:entry];
    [_entryMap removeObjectForKey:key];
}


- (MobileBackupEntry *) entryWithKey:(MobileBackupKey *)key
{
    if (!key) return nil;
    return [_entryMap objectForKey:key];
}


- (void) moveEntry:(MobileBackupEntry *)entry toKey:(MobileBackupKey *)key
{
    MobileBackupKey *oldKey = [entry key];
    if ([key isEqual:oldKey]) return;

    [entry setKey:key];
    [_entryMap setObject:entry forKey:key];
    [_entryMap removeObjectForKey:oldKey];
}


- (NSArray *) contentsOfDirectoryWithKey:(MobileBackupKey *)key
{
    return [[_directoryMap objectForKey:key] allObjects];
}


- (void) flushChanges
{
    NSMutableData *data = [NSMutableData data];
    
    DataWriter *writer = DataWriterCreate(data);

    DataWriterWriteUInt8(writer, 'm');
    DataWriterWriteUInt8(writer, 'b');
    DataWriterWriteUInt8(writer, 'd');
    DataWriterWriteUInt8(writer, 'b');
    DataWriterWriteUInt8(writer, _version);
    DataWriterWriteUInt8(writer, 0);
    
    for (MobileBackupEntry *entry in _entries) {
        [entry _writeToWriter:writer];
    }

    [data writeToFile:_path atomically:YES];

    DataWriterFree(writer);
}


@end


@implementation MobileBackupKey

- (id) initWithDomain:(NSString *)domain path:(NSString *)path
{
    if ((self = [super init])) {
        _domain = domain;
        _path   = path;
    }
    
    return self;
}

- (NSUInteger) hash
{
    return [_domain hash] ^ [_path hash];
}


- (id) copyWithZone:(NSZone *)zone
{
    return self;
}


- (BOOL) isEqual:(id)object
{
    if (![object isKindOfClass:[MobileBackupKey class]]) {
        return NO;
    }
    
    MobileBackupKey *otherKey = (MobileBackupKey *)object;
    
    NSString *otherDomain = [otherKey domain];
    NSString *otherPath   = [otherKey path];
    
    BOOL domainEqual = (!_domain && !otherDomain) || [_domain isEqualToString:otherDomain];
    BOOL pathEqual   = (!_path   && !otherPath)   || [_path   isEqualToString:otherPath];
    
    return domainEqual && pathEqual;
}


- (NSString *) localFilename
{
    NSString *key = [NSString stringWithFormat:@"%@-%@", _domain, _path];

    NSData *hash = CreateSHA1Hash([key dataUsingEncoding:NSUTF8StringEncoding]);
    return GetHexStringWithData(hash);
}


@end



@implementation MobileBackupEntry {
    NSMutableArray *_propertyKeys;
    NSMutableDictionary *_properties;
    BOOL _modified;
}

- (id) _initWithReader:(DataReader *)reader
{
    if ((self = [super init])) {
        [self _fillWithReader:reader];
    }

    return self;
}


- (void) _updateHashAndLength
{
    NSData *contents = [self contents];

    _fileLength = [contents length];
    _hash = CreateSHA1Hash(contents);

    [_parentManifest flushChanges];
}


- (void) _fillWithReader:(DataReader *)reader
{
    NSString *domain = DataReaderReadString(reader);
    NSString *path   = DataReaderReadString(reader);
    
    _key           = [[MobileBackupKey alloc] initWithDomain:domain path:path];
    _linkTarget    = DataReaderReadString(reader);
    _hash          = DataReaderReadData(reader);
    _encryptionKey = DataReaderReadData(reader);

    _mode    = DataReaderReadUInt16(reader);
    _inode   = DataReaderReadUInt64(reader);
    _userID  = DataReaderReadUInt32(reader);
    _groupID = DataReaderReadUInt32(reader);

    _lastModifiedTime = DataReaderReadUInt32(reader);
    _lastAccessedTime = DataReaderReadUInt32(reader);
    _createdTime      = DataReaderReadUInt32(reader);

    _fileLength = DataReaderReadUInt64(reader);
    
    _flag = DataReaderReadUInt8(reader);


    UInt8 propertyCount = DataReaderReadUInt8(reader);

    NSMutableDictionary *properties = [NSMutableDictionary dictionaryWithCapacity:propertyCount];
    NSMutableArray *propertyKeys = [NSMutableArray arrayWithCapacity:propertyCount];

    for (NSInteger i = 0; i < propertyCount; i++) {
        NSString *key   = DataReaderReadString(reader);
        id value = DataReaderReadString(reader);
        
        if (!key) continue;

        if (!value) {
            value = [NSNull null];
        }

        [propertyKeys addObject:key];
        [properties setObject:value forKey:key];
    }

    _propertyKeys = propertyKeys;
    _properties = properties;
}


- (void) _writeToWriter:(DataWriter *)writer
{
    DataWriterWriteString(writer, [_key domain]);
    DataWriterWriteString(writer, [_key path]);
    DataWriterWriteString(writer, _linkTarget);
    DataWriterWriteData  (writer, _hash);
    DataWriterWriteData  (writer, _encryptionKey);

    DataWriterWriteUInt16(writer, _mode);
    DataWriterWriteUInt64(writer, _inode);
    DataWriterWriteUInt32(writer, _userID);
    DataWriterWriteUInt32(writer, _groupID);

    DataWriterWriteUInt32(writer, _lastModifiedTime);
    DataWriterWriteUInt32(writer, _lastAccessedTime);
    DataWriterWriteUInt32(writer, _createdTime);
    
    DataWriterWriteUInt64(writer, _fileLength);
    
    DataWriterWriteUInt8(writer, _flag);

    DataWriterWriteUInt8(writer, [_propertyKeys count]);
    
    for (NSString *key in _propertyKeys) {
        DataWriterWriteString(writer, key);

        NSString *value = [_properties objectForKey:key];
        if ([value isKindOfClass:[NSNull class]]) {
            DataWriterWriteString(writer, nil);
        } else {
            DataWriterWriteString(writer, value);
        }
    }
}


- (void) setPropertyValue:(NSString *)value forKey:(NSString *)key
{
    NSString *existing = [_properties objectForKey:key];
    
    if (!existing && value) {
        [_properties setObject:value forKey:key];
        [_propertyKeys addObject:key];
        _modified = YES;

    } else if (existing && !value) {
        [_properties removeObjectForKey:key];
        [_propertyKeys removeObject:key];
        _modified = YES;

    } else if (![existing isEqual:value]) {
        [_properties setObject:value forKey:key];
        _modified = YES;
    }
}


- (id) propertyValueForKey:(NSString *)key
{
    return [_properties objectForKey:key];
}


- (MobileBackupOpenedFile *) creatWithMode:(int)mode error:(NSError **)error
{
    int fd = creat([[self localPathInBackup] UTF8String], mode);

    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return nil;
    }

    MobileBackupOpenedFile *file = [[MobileBackupOpenedFile alloc] _initWithFileDescriptor:fd];
    [file setParentEntry:self];
    return file;
}


- (MobileBackupOpenedFile *) openWithMode:(int)mode error:(NSError **)error
{
    int fd = open([[self localPathInBackup] UTF8String], mode);

    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return nil;
    }

    MobileBackupOpenedFile *file = [[MobileBackupOpenedFile alloc] _initWithFileDescriptor:fd];
    [file setParentEntry:self];
    return file;
}


- (NSString *) localPathInBackup
{
    NSString *localFilename = [_key localFilename];
    return [[[_parentManifest path] stringByDeletingLastPathComponent] stringByAppendingPathComponent:localFilename];
}


- (void) updateContents:(NSData *)contents
{
    [contents writeToFile:[self localPathInBackup] atomically:YES];
    [self _updateHashAndLength];
}


- (NSData *) contents
{
    return [NSData dataWithContentsOfFile:[self localPathInBackup]];
}


@end


@implementation MobileBackupOpenedFile {
    int _fd;
}


- (id) _initWithFileDescriptor:(int)fd
{
    if ((self = [super init])) {
        _fd = fd;
    }
    
    return self;
}


- (void) close
{
    close(_fd);
    [_parentEntry _updateHashAndLength];
}


- (ssize_t) readIntoBuffer:(char *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)error
{
    ssize_t result = pread(_fd, buffer, size, offset);

    if (result < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return -1;
    }
    
    return result;
}


- (ssize_t) writeFromBuffer:(const char *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)error;
{
    ssize_t result = pwrite(_fd, buffer, size, offset);

    if (result < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return -1;
    }

    return result;
}


@end
