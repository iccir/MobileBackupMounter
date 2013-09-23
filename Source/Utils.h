/*
    Utils.h
    MobileBackupMounter
    (c) 2013 Ricci Adams
    MIT license, http://www.opensource.org/licenses/mit-license.php
*/


#import <Foundation/Foundation.h>

typedef struct DataReader DataReader;
typedef struct DataWriter DataWriter;

extern NSData *CreateSHA1Hash(NSData *inData);
extern NSData *GetDataWithHexString(NSString *inputString);
extern NSString *GetHexStringWithData(NSData *data);

extern DataReader *DataReaderCreate(NSData *data);
extern void DataReaderFree(DataReader *reader);

extern BOOL DataReaderIsValid(DataReader *reader);
extern BOOL DataReaderHasBytesAvailable(DataReader *reader);

extern UInt8 DataReaderReadUInt8(DataReader *reader);
extern UInt16 DataReaderReadUInt16(DataReader *reader);
extern UInt32 DataReaderReadUInt32(DataReader *reader);
extern UInt64 DataReaderReadUInt64(DataReader *reader);

extern NSData *DataReaderReadData(DataReader *reader);
extern NSString *DataReaderReadString(DataReader *reader);

extern DataWriter *DataWriterCreate(NSMutableData *data);
extern void DataWriterFree(DataWriter *writer);

extern void DataWriterWriteUInt8 ( DataWriter *writer, UInt8 u);
extern void DataWriterWriteUInt16( DataWriter *writer, UInt16 u);
extern void DataWriterWriteUInt32( DataWriter *writer, UInt32 u);
extern void DataWriterWriteUInt64( DataWriter *writer, UInt64 u);
extern void DataWriterWriteData  ( DataWriter *writer, NSData *d);
extern void DataWriterWriteString( DataWriter *writer, NSString *s);
