/*
    Utils.m
    MobileBackupMounter
    (c) 2013 Ricci Adams
    MIT license, http://www.opensource.org/licenses/mit-license.php
*/


#import "Utils.h"

#import <CommonCrypto/CommonCrypto.h>

struct DataReader {
    const UInt8 *b;
    const UInt8 *bytes;
    const UInt8 *end;
    NSUInteger length;
    BOOL valid;
};




NSData *CreateSHA1Hash(NSData *inData)
{
    static const size_t digestLength = 20;
    unsigned char digest[digestLength];

    CC_SHA1_CTX ctx;

    CC_SHA1_Init(&ctx);
    CC_SHA1_Update(&ctx, [inData bytes], (CC_LONG)[inData length]);
    CC_SHA1_Final(digest, &ctx);
    
    return [[NSData alloc] initWithBytes:digest length:digestLength];
}


NSData *GetDataWithHexString(NSString *inputString)
{
    NSUInteger inLength = [inputString length];
    
    unichar *inCharacters = alloca(sizeof(unichar) * inLength);
    [inputString getCharacters:inCharacters range:NSMakeRange(0, inLength)];

    UInt8 *outBytes = malloc(sizeof(UInt8) * ((inLength / 2) + 1));

    NSInteger i, o = 0;
    UInt8 outByte = 0;
    for (i = 0; i < inLength; i++) {
        UInt8 c = inCharacters[i];
        SInt8 value = -1;
        
        if      (c >= '0' && c <= '9') value =      (c - '0');
        else if (c >= 'A' && c <= 'F') value = 10 + (c - 'A');
        else if (c >= 'a' && c <= 'f') value = 10 + (c - 'a');            
        
        if (value >= 0) {
            if (i % 2 == 1) {
                outBytes[o++] = (outByte << 4) | value;
                outByte = 0;
            } else {
                outByte = value;
            }

        } else {
            if (o != 0) break;
        }        
    }

    return [NSData dataWithBytesNoCopy:outBytes length:o freeWhenDone:YES];
}


NSString *GetHexStringWithData(NSData *data)
{
    NSUInteger inLength  = [data length];
    unichar *outCharacters = malloc(sizeof(unichar) * (inLength * 2));

    UInt8 *inBytes = (UInt8 *)[data bytes];
    static const char lookup[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };
 
    NSUInteger i, o = 0;
    for (i = 0; i < inLength; i++) {
        UInt8 inByte = inBytes[i];
        outCharacters[o++] = lookup[(inByte & 0xF0) >> 4];
        outCharacters[o++] = lookup[(inByte & 0x0F)];
    }

    return [[NSString alloc] initWithCharactersNoCopy:outCharacters length:o freeWhenDone:YES];
}


DataReader *DataReaderCreate(NSData *data)
{
    DataReader *result = malloc(sizeof(DataReader));
    
    result->bytes  = [data bytes];
    result->length = [data length];
    result->b      = result->bytes;
    result->end    = result->bytes + result->length;
    result->valid  = YES;
    
    return result;
}


void DataReaderFree(DataReader *reader)
{
    free(reader);
}


BOOL DataReaderIsValid(DataReader *reader)
{
    return reader->valid;
}


BOOL DataReaderHasBytesAvailable(DataReader *reader)
{
    return reader->b < reader->end;
}


static BOOL sDataReaderEnsure(DataReader *reader, NSUInteger length)
{
    BOOL yn = ((reader->b + length) <= (reader->end));
    if (!yn) reader->valid = NO;
    return yn;
}



UInt8 DataReaderReadUInt8(DataReader *reader)
{
    if (!sDataReaderEnsure(reader, 1)) return 0;

    UInt8 result = *(UInt8 *)reader->b;
    reader->b++;
    return result;
}


UInt16 DataReaderReadUInt16(DataReader *reader)
{
    if (!sDataReaderEnsure(reader, 2)) return 0;

    UInt16 result = *(UInt16 *)reader->b;
    reader->b += 2;
    return ntohs(result);
}


UInt32 DataReaderReadUInt32(DataReader *reader)
{
    if (!sDataReaderEnsure(reader, 4)) return 0;

    UInt32 result = *(UInt32 *)reader->b;
    reader->b += 4;
    return ntohl(result);
}


UInt64 DataReaderReadUInt64(DataReader *reader)
{
    if (!sDataReaderEnsure(reader, 8)) return 0;

    UInt64 result = *(UInt64 *)reader->b;
    reader->b += 8;

#if TARGET_RT_LITTLE_ENDIAN
    return __DARWIN_OSSwapInt64(result);
#else
    return result;
#endif
}


NSData *DataReaderReadData(DataReader *reader)
{
    UInt16 length = DataReaderReadUInt16(reader);

    if (length == 0xFFFF) return nil;

    NSData *result = [[NSData alloc] initWithBytes:reader->b length:length];
    reader->b += length;
    return result;
}


NSString *DataReaderReadString(DataReader *reader)
{
    UInt16 length = DataReaderReadUInt16(reader);

    if (length == 0xFFFF) return nil;

    NSString *result = [[NSString alloc] initWithBytes:reader->b length:length encoding:NSUTF8StringEncoding];
    reader->b += length;
    return result;
}


DataWriter *DataWriterCreate(NSMutableData *data)
{
    return (DataWriter *)CFBridgingRetain(data);
}


void DataWriterFree(DataWriter *writer)
{
    CFBridgingRelease((CFTypeRef)writer);
}


void DataWriterWriteUInt8(DataWriter *writer, UInt8 u)
{
    CFMutableDataRef data = (CFMutableDataRef)writer;
    CFDataAppendBytes(data, &u, 1);
}


void DataWriterWriteUInt16( DataWriter *writer, UInt16 u)
{
    CFMutableDataRef data = (CFMutableDataRef)writer;
    u = htons(u);
    CFDataAppendBytes(data, (void *)&u, 2);
}


void DataWriterWriteUInt32( DataWriter *writer, UInt32 u)
{
    CFMutableDataRef data = (CFMutableDataRef)writer;
    u = htonl(u);
    CFDataAppendBytes(data, (void *)&u, 4);
}


void DataWriterWriteUInt64( DataWriter *writer, UInt64 u)
{
    CFMutableDataRef data = (CFMutableDataRef)writer;

#if TARGET_RT_LITTLE_ENDIAN
    u = __DARWIN_OSSwapInt64(u);
#endif

    CFDataAppendBytes(data, (void *)&u, 8);
}


void DataWriterWriteData(DataWriter *writer, NSData *d)
{
    NSUInteger   length = [d length];
    const UInt8 *bytes  = [d bytes];

    if (!bytes || length >= 0xFFFF) {
        length = 0xFFFF;
        bytes  = NULL;
    }

    DataWriterWriteUInt16(writer, length);
    
    if (bytes) {
        CFMutableDataRef data = (CFMutableDataRef)writer;
        CFDataAppendBytes(data, bytes, length);
    }
}


void DataWriterWriteString( DataWriter *writer, NSString *s)
{
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    DataWriterWriteData(writer, d);
}
