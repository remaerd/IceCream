//
//  Object+CKRecord.swift
//  IceCream
//
//  Created by 蔡越 on 11/11/2017.
//

import Foundation
import CloudKit
import RealmSwift

public protocol CKRecordConvertible: CKRecordConnectable {
    static var recordType: String { get }
    static var customZoneID: CKRecordZoneID { get }
    
    var recordID: CKRecordID { get }
    var record: CKRecord { get }
    
    var isDeleted: Bool { get }
}

extension CKRecordConvertible where Self: Object {
    
    public static var recordType: String {
        return className()
    }
    
    public static var customZoneID: CKRecordZoneID {
        return CKRecordZoneID(zoneName: "\(recordType)sZone", ownerName: CKCurrentUserDefaultName)
    }
    
    /// recordName : this is the unique identifier for the record, used to locate records on the database. We can create our own ID or leave it to CloudKit to generate a random UUID.
    /// For more: https://medium.com/@guilhermerambo/synchronizing-data-with-cloudkit-94c6246a3fda
    public var recordID: CKRecordID {
        guard let sharedSchema = Self.sharedSchema() else {
            fatalError("No schema settled. Go to Realm Community to seek more help.")
        }
        
        guard let primaryKeyProperty = sharedSchema.primaryKeyProperty else {
            fatalError("You should set a primary key on your Realm object")
        }
        
        if let primaryValueString = self[primaryKeyProperty.name] as? String {
            return CKRecordID(recordName: primaryValueString, zoneID: Self.customZoneID)
        } else if let primaryValueInt = self[primaryKeyProperty.name] as? Int {
            return CKRecordID(recordName: "\(primaryValueInt)", zoneID: Self.customZoneID)
        } else {
            fatalError("Primary key should be String or Int")
        }
    }
    
    // Simultaneously init CKRecord with zoneID and recordID, thanks to this guy: https://stackoverflow.com/questions/45429133/how-to-initialize-ckrecord-with-both-zoneid-and-recordid
    public var record: CKRecord {
        let r = CKRecord(recordType: Self.recordType, recordID: recordID)
        let properties = objectSchema.properties
        for prop in properties {
            switch prop.type {
            case .int, .string, .bool, .date, .float, .double, .data:
                r[prop.name] = self[prop.name] as? CKRecordValue
            case .object:
                guard let objectName = prop.objectClassName else { break }
                // Convert object as CreamAsset
				if objectName == CreamAsset.className() {
					if let creamAsset = self[prop.name] as? CreamAsset {
						r[prop.name] = creamAsset.asset
					} else {
						/// Just a warm hint:
						/// When we set nil to the property of a CKRecord, that record's property will be hidden in the CloudKit Dashboard
						r[prop.name] = nil
					}
				}
				else if let references = Self.references
				{
					for reference in references
					{
						if objectName == reference.className() 
						{
							// MARK: Convert object as One to Many relationship.
							if let object = self[prop.name] as? Object
							{
								guard let primaryKey = object.objectSchema.primaryKeyProperty?.name,
                                      let id = object.value(forKey: primaryKey) as? String else { break }
								r[prop.name] = CKReference(recordID: CKRecordID(recordName: id), action: .none)
							}
							// MARK: Convert object as Many to Many relationship.
							else if let listBase = self[prop.name] as? ListBase
							{
								// MARK: self[prop.name] cannot parsed as an List<Object>. So it has to cast as low level object ListBase and read _rlmArray data from it.
								var referenceList = [CKReference]()
								for index in 0..<listBase._rlmArray.count
								{
									guard let object = listBase._rlmArray[index] as? Object,
										let primaryKey = object.objectSchema.primaryKeyProperty?.name,
										let id = object.value(forKey: primaryKey) as? String else { break }
									referenceList.append(CKReference(recordID: CKRecordID(recordName: id), action: .none))
								}
								r[prop.name] = referenceList as CKRecordValue
							}
						}
					}
				}
            default: break
            }
        }
        return r
    }
    
}


