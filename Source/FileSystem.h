/*
    FileSystem.h
    MobileBackupMounter
    (c) 2013 Ricci Adams
    MIT license, http://www.opensource.org/licenses/mit-license.php
*/

@interface FileSystem : NSObject

- (id) initWithPath:(NSString *)path;

- (void) mount;
- (void) unmount;

@end
