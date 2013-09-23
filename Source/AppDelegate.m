/*
    AppDelegate.m
    MobileBackupMounter
    (c) 2013 Ricci Adams
    MIT license, http://www.opensource.org/licenses/mit-license.php
*/

#import "AppDelegate.h"
#import "FileSystem.h"


@implementation AppDelegate {
    FileSystem *_fs;
}

- (void) applicationDidFinishLaunching:(NSNotification *)notification
{
    // Hardcoded path for now
    _fs = [[FileSystem alloc] initWithPath:@"/Users/iccir/Library/Application Support/MobileSync/Backup/c5ed34c7335faab6951fcce61640db0b62e2bd9a-20130922-005858"];
    [_fs mount];
}


- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication *)sender
{
    [_fs unmount];
    return NSTerminateNow;
}


@end
