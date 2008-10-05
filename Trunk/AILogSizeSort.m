/* 
 * $Id$
 *
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 *
 * This plugin is copyright (c) 2008 Jon Chambers.  The plugin's official site is:
 * http://projects.eatthepath.com/sort-by-log-size-plugin/
 * 
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import "AILogSizeSort.h"
#import "AILoggerPlugin.h"

#import <Adium/AISharedAdium.h>

#import <AIUtilities/AITigerCompatibility.h> 
#import <AIUtilities/AIStringUtilities.h>

#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIListObject.h>
#import <Adium/AIMetaContact.h>

#import <Adium/ESDebugAILog.h>

@implementation AILogSizeSort

/*!
 * @brief Did become active first time
 *
 * Called only once; gives the sort controller an opportunity to set defaults and load preferences lazily.
 */
- (void)didBecomeActiveFirstTime
{
	AILog(@"Sort by log size controller became active for first time.");
	logSizeCache = [[NSMutableDictionary alloc] init];
	AILog(@"%@", logSizeCache);
}

/*!
 * @brief Non-localized identifier
 */
- (NSString *)identifier{
    return @"Log size";
}

/*!
 * @brief Localized display name
 */
- (NSString *)displayName{
    return AILocalizedString(@"Sort Contacts by Log Size",nil);
}

/*!
 * @brief Properties which, when changed, should trigger a resort
 */
- (NSSet *)statusKeysRequiringResort{
	return nil;
}

/*!
 * @brief Attribute keys which, when changed, should trigger a resort
 */
- (NSSet *)attributeKeysRequiringResort{
	return nil;
}

#pragma mark Configuration
/*!
 * @brief Window title when configuring the sort
 *
 * Subclasses should provide a title for configuring the sort only if configuration is possible.
 * @result Localized title. If nil, the menu item will be disabled.
 */
- (NSString *)configureSortWindowTitle{
	return nil;
}

/*!
 * @brief Nib name for configuration
 */
- (NSString *)configureNibName{
	return nil;
}

/*!
 * @brief View did load
 */
- (void)viewDidLoad{
}

/*!
 * @brief Preference changed
 *
 * Sort controllers should live update as preferences change.
 */
- (IBAction)changePreference:(id)sender
{
}

/*!
 * @brief Allow users to manually sort groups
 */
-(BOOL)canSortManually
{
	return YES;
}

-(unsigned long long)getCachedLogSize:(AIListContact *)listContact
{
	AILogWithSignature(@"Getting cached log size for %@/%@.", [[listContact account] explicitFormattedUID], [listContact UID]);
	
	if([logSizeCache valueForKey:[[listContact account] explicitFormattedUID]] == nil)
	{
		[logSizeCache setValue:[[NSMutableDictionary alloc] init] forKey:[[listContact account] explicitFormattedUID]];
	}
	
	NSMutableDictionary *accountDictionary = [logSizeCache valueForKey:[[listContact account] explicitFormattedUID]];
	
	if([accountDictionary valueForKey:[listContact UID]] == nil)
	{
		AILogWithSignature(@"\tNo cache hit.");
		[accountDictionary setValue:[NSNumber numberWithUnsignedLongLong:[AILogSizeSort getContactLogSize:listContact]] forKey: [listContact UID]];
	}
	
	AILogWithSignature(@"\tLog file size: %@", [accountDictionary valueForKey:[listContact UID]]);
	return [[accountDictionary valueForKey:[listContact UID]] unsignedLongLongValue];
}

/*!
 * @brief Returns the total aggregate log size for a contact
 *
 * Returns the total aggregate log size for a contact.  For meta-contacts, the
 * total log file size of all sub-contacts is returned.  If no log exists or if
 * something else goes wrong, 0 is returned.
 *
 * @param listContact an AIListContact for which to retrieve a total log file size
 * @return the total log file size in bytes or 0 if an error occurred
 */
+(unsigned long long)getContactLogSize:(AIListContact *)listContact
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	if([listContact isMemberOfClass:[AIMetaContact class]])
	{
		// Recurse through all sub-contacts
		id contact;
		unsigned long long size = 0;
		
		NSEnumerator *contactEnumerator = [[(AIMetaContact *)listContact listContacts] objectEnumerator];

		while(contact = [contactEnumerator nextObject])
		{
			size += [AILogSizeSort getContactLogSize:contact];
		}
		
		return size;
	}
	else
	{
		// Find the path to the directory containing the log files for this contact
		NSString *path = [[AILoggerPlugin logBasePath] stringByAppendingPathComponent:[AILoggerPlugin relativePathForLogWithObject:[listContact UID] onAccount: [listContact account]]];
		
		// Grab an enumerator for all log files for this contact
		NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:path];
		NSString *file;
		
		unsigned long long size = 0;
		
		while(file = [dirEnum nextObject])
		{
			NSDictionary *fileAttributes = [fileManager fileAttributesAtPath:[path stringByAppendingPathComponent:file] traverseLink:YES];
			
			if (fileAttributes != nil)
			{
				NSNumber *fileSize;
				if(fileSize = [fileAttributes objectForKey:NSFileSize])
				{
					size += [fileSize unsignedLongLongValue];
				}
			}
		}
		
		return size;
	}
}

#pragma mark Sorting
/*!
 * @brief Sort by log size
 */
int logSizeSort(id objectA, id objectB, BOOL groups)
{
	if(groups)
	{
		// Keep groups in manual order (borrowed from ESStatusSort)
		if ([objectA orderIndex] > [objectB orderIndex])
		{
			return NSOrderedDescending;
		}
		else
		{
			return NSOrderedAscending;
		}
	}
	
	// Get a reference to one and only AILogSizeSort instance.  If this sorting method is being
	// called, it should always be the case that AILogSizeSort is the active sort controller.
	AISortController *sortController = [[adium contactController] activeSortController];
	
	unsigned long long sizeA = 0;
	unsigned long long sizeB = 0;
	
	if([sortController isMemberOfClass:[AILogSizeSort class]])
	{
		sizeA = [(AILogSizeSort *)sortController getCachedLogSize:objectA];
		sizeB = [(AILogSizeSort *)sortController getCachedLogSize:objectB];
	}
	else
	{
		sizeA = [AILogSizeSort getContactLogSize:objectA];
		sizeB = [AILogSizeSort getContactLogSize:objectB];
	}

	if(sizeB == sizeA)
	{
		// Fall back to basic alphabetical sorting in the event of a tie.
		return [[objectA displayName] caseInsensitiveCompare:[objectB displayName]];
	}
	else if(sizeA > sizeB)
	{
		// There's a clear winner; run with it.
		return NSOrderedAscending;
	}
	else
	{
		return NSOrderedDescending;
	}
}

/*!
 * @brief Sort function
 */
- (sortfunc)sortFunction{
	return &logSizeSort;
}
@end
