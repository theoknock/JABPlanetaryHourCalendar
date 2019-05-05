//
//  ViewController.m
//  JABPlanetaryHourCalendar
//
//  Created by Xcode Developer on 4/21/19.
//  Copyright © 2019 The Life of a Demoniac. All rights reserved.
//

#import "ViewController.h"
#import <JABPlanetaryHourCocoaTouchFramework/JABPlanetaryHourCocoaTouchFramework.h>


@interface ViewController ()
{
    __block EKEventStore *eventStore;
}

@end

@implementation ViewController

EKEvent *(^planetaryHourEvent)(EKEventStore *, EKCalendar *, NSDictionary<NSNumber *,id> * _Nonnull, CLLocationCoordinate2D) = ^(EKEventStore *planetaryHourEventStore, EKCalendar *planetaryHourCalendar, NSDictionary<NSNumber *,id> * _Nonnull planetaryHourData, CLLocationCoordinate2D referenceCoordinate)
{
    EKEvent *event     = [EKEvent eventWithEventStore:planetaryHourEventStore];
    event.timeZone     = [NSTimeZone localTimeZone];
    event.calendar     = planetaryHourCalendar;
    event.title        = [NSString stringWithFormat:@"%@ %@", (NSString *)[(NSAttributedString *)[planetaryHourData objectForKey:@(Symbol)] string], [planetaryHourData objectForKey:@(Name)]];
    event.availability = EKEventAvailabilityFree;
    event.alarms       = @[[EKAlarm alarmWithAbsoluteDate:[planetaryHourData objectForKey:@(StartDate)]]];
    event.location     = [NSString stringWithFormat:@"%f, %f", referenceCoordinate.latitude, referenceCoordinate.longitude];
    event.notes        = [NSString stringWithFormat:@"Hour %lu", ((NSNumber *)[planetaryHourData objectForKey:@(Hour)]).integerValue + 1];
    event.startDate    = [planetaryHourData objectForKey:@(StartDate)];
    event.endDate      = [planetaryHourData objectForKey:@(EndDate)];
    event.allDay       = NO;
    
    return event;
};

- (void)calendarPlanetaryHours
{
    NSLog(@"OBSERVED: PlanetaryHoursDataSourceUpdatedNotification");
    [eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError * _Nullable error) {
        if (granted)
        {
            // Remove any existing Planetary Hours calendar
            NSArray <EKCalendar *> *calendars = [eventStore calendarsForEntityType:EKEntityTypeEvent];
            [calendars enumerateObjectsUsingBlock:^(EKCalendar * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([obj.title isEqualToString:@"Planetary Hour"]) {
                    NSLog(@"Existing planetary hour calendar found...");
                    NSLog(@"Removing existing planetary hour calendar...");
                    *stop = TRUE;
                    __autoreleasing NSError *error;
                    if ([eventStore removeCalendar:obj commit:TRUE error:&error])
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NSLog(@"Planetary hour calendar removed.");
                            NSLog(@"Removing existing planetary hour calendar...");
                            __autoreleasing NSError *removeOldCalendarError;
                            if ([eventStore saveCalendar:obj commit:TRUE error:&removeOldCalendarError])
                                NSLog(@"Changes saved to event store");
                            __block EKCalendar *calendar = [EKCalendar calendarForEntityType:EKEntityTypeEvent eventStore:eventStore];
                            calendar.title = @"Planetary Hour";
                            calendar.source = eventStore.sources[1];
                            __autoreleasing NSError *error;
                            if ([eventStore saveCalendar:calendar commit:TRUE error:&error])
                            {
                                if (error)
                                {
                                    NSLog(@"Error creating new planetary hour calendar: %@\nCreating a default calendar for new planetary hour events...", error.localizedDescription);
                                    calendar = [eventStore defaultCalendarForNewEvents];
                                } else {
                                    NSLog(@"New planetary hour calendar created...");
                                }
                                
                                NSIndexSet *daysIndices  = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, 365)];      // Calendar one year of events, starting today
                                NSMutableIndexSet *dataIndices  = [[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, 4)];
                                [dataIndices addIndex:6];                                                                       // Return 0-4 and  indices of planetary hour data
                                NSIndexSet *hoursIndices = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, 24)];      // Generate data for each planetary hour of the day
                                CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(PlanetaryHourDataSource.data.locationManager.location.coordinate.latitude, PlanetaryHourDataSource.data.locationManager.location.coordinate.longitude);
                                [PlanetaryHourDataSource.data solarCyclesForDays:daysIndices planetaryHourData:dataIndices planetaryHours:hoursIndices
                                                       solarCycleCompletionBlock:nil
                                                    planetaryHourCompletionBlock:^(NSDictionary<NSNumber *,id> * _Nonnull planetaryHour) {
                                                        [eventStore saveEvent:planetaryHourEvent(eventStore, calendar, planetaryHour, coordinate) span:EKSpanThisEvent commit:FALSE error:nil];
                                                    } planetaryHoursCompletionBlock:^(NSArray<NSDictionary<NSNumber *,NSDate *> *> * _Nonnull planetaryHours) {
                                                        if ([eventStore commit:nil])
                                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                                [self.datePicker setDate:[planetaryHours[0] objectForKey:@(StartDate)]];
                                                            });
                                                    } planetaryHourDataSourceCompletionBlock:^(NSError * _Nullable error) {
                                                        if (error)
                                                            NSLog(@"JABPlanetaryHourFramework error: %@", error.description);
                                                        else
                                                            NSLog(@"JABPlanetaryHourFramework calculations complete");
                                                        
                                                        if ([eventStore saveCalendar:calendar commit:TRUE error:nil])
                                                            NSLog(@"New planetary hour calendar saved.");
                                                        else
                                                            NSLog(@"Error saving new planetary hour calendar.");
                                                    }];
                            }
                            else
                                NSLog(@"Error saving changes to event store:\t%@", removeOldCalendarError.description);
                            
                        });
                    else
                        NSLog(@"Error removing planetary hour calendar:/t%@", error.description);
                }
            }];
            
            
            
        } else {
            NSLog(@"Access to event store denied: %@", error.description);
        }
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    eventStore = [[EKEventStore alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(calendarPlanetaryHours) name:@"PlanetaryHoursDataSourceUpdatedNotification" object:nil];
    [PlanetaryHourDataSource.data.locationManager requestLocation];
}

//NSDate *(^floorSecondsForDate)(NSDate *) = ^(NSDate *date) {
//    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
//    NSDateComponents *components     = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:date];
//    NSDateComponents *new_components = [NSDateComponents new];
//    new_components.year              = components.year;
//    new_components.month             = components.month;
//    new_components.day               = components.day;
//    new_components.hour              = components.hour;
//    new_components.minute            = components.minute;
//    new_components.second            = 0;
//    NSDate *new_date = [calendar dateFromComponents:new_components];
//
//    return new_date;
//};

//EKEvent *(^solarCycleEvent)(EKEventStore *, EKCalendar *, NSDictionary<NSNumber *,NSDate *> * _Nonnull, CLLocationCoordinate2D) = ^(EKEventStore *solarCycleEventStore, EKCalendar *solarCycleCalendar, NSDictionary<NSNumber *,NSDate *> * _Nonnull solarCycleData, CLLocationCoordinate2D referenceCoordinate)
//{
//    for (NSNumber *solarCycleDate in @[@(SolarCycleDateStart), @(SolarCycleDateMid)])
//    {
//        EKEvent *event     = [EKEvent eventWithEventStore:solarCycleEventStore];
//        event.timeZone     = [NSTimeZone localTimeZone];
//        event.calendar     = solarCycleCalendar;
//        event.title        = @"Day";
//        event.availability = EKEventAvailabilityFree;
//        event.alarms       = @[[EKAlarm alarmWithAbsoluteDate:[solarCycle objectForKey:@(SolarCycleDateStart)]]];
//        event.location     = [NSString stringWithFormat:@"%f, %f", coordinate.latitude, coordinate.longitude];
//        event.notes        = @"";
//        event.startDate    = [solarCycle objectForKey:@(SolarCycleDateStart)];
//        event.endDate      = [solarCycle objectForKey:@(SolarCycleDateMid)];
//        event.allDay       = NO;
//
//        return event;
//    }
//
//};

@end

