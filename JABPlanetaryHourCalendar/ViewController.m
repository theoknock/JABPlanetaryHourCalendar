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

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    EKEventStore *eventStore = [[EKEventStore alloc] init];
    [eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError * _Nullable error) {
        if (granted)
        {
            NSArray <EKCalendar *> *calendars = [eventStore calendarsForEntityType:EKEntityTypeEvent];
            [calendars enumerateObjectsUsingBlock:^(EKCalendar * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([obj.title isEqualToString:@"Planetary Hour"]) {
                    NSLog(@"Planetary Hour calendar found.");
                    __autoreleasing NSError *error;
                    if ([eventStore removeCalendar:obj commit:TRUE error:&error])
                    {
                        NSLog(@"Planetary hour calendar removed.");
                    } else {
                        NSLog(@"Error removing planetary hour calendar/t%@", error.description);
                    }
                }
            }];
            EKCalendar *calendar = [EKCalendar calendarForEntityType:EKEntityTypeEvent eventStore:eventStore];
            calendar.title = @"Planetary Hour";
            calendar.source = eventStore.sources[1];
            __autoreleasing NSError *error;
            if ([eventStore saveCalendar:calendar commit:TRUE error:&error])
            {
                if (error)
                {
                    NSLog(@"Error saving new calendar: %@\nUsing default calendar for new events...", error.localizedDescription);
                    calendar = [eventStore defaultCalendarForNewEvents];
                }
                
                NSIndexSet *daysIndices  = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, 30)];      // Calendar one year of events, starting today
                NSIndexSet *dataIndices  = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, 8)];       // Return all data generated for a planetary hour
                NSIndexSet *hoursIndices = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, 24)];      // Generate data for each planetary hour of the day
                __block int dayCounter = 0;
                [PlanetaryHourDataSource.data
                 solarCyclesForDays:daysIndices
                 planetaryHourData:dataIndices
                 planetaryHours:hoursIndices
                 solarCycleCompletionBlock:^(NSDictionary<NSNumber *,NSDate *> * _Nonnull solarCycle) {
                     
                 }
                 planetaryHourCompletionBlock:^(NSDictionary<NSNumber *,id> * _Nonnull planetaryHour) {
                     EKEvent *event     = [EKEvent eventWithEventStore:eventStore];
                     event.timeZone     = [NSTimeZone localTimeZone];
                     event.calendar     = calendar;
                     event.title        = [NSString stringWithFormat:@"%@ %@", (NSString *)[(NSAttributedString *)[planetaryHour objectForKey:@(Symbol)] string], [planetaryHour objectForKey:@(Name)]];
                     event.availability = EKEventAvailabilityFree;
                     EKAlarm *alarm     = [EKAlarm alarmWithAbsoluteDate:[planetaryHour objectForKey:@(StartDate)]];
                     event.alarms       = @[alarm];
                     event.location     = [NSString stringWithFormat:@"%f, %f", PlanetaryHourDataSource.data.locationManager.location.coordinate.latitude, PlanetaryHourDataSource.data.locationManager.location.coordinate.longitude];
                     event.notes        = [NSString stringWithFormat:@"%lu", ((NSNumber *)[planetaryHour objectForKey:@(Hour)]).integerValue];
                     event.startDate    = [planetaryHour objectForKey:@(StartDate)];
                     event.endDate      = [planetaryHour objectForKey:@(EndDate)];
                     event.allDay       = NO;
                     
                     __autoreleasing NSError *saveEventError;
                     if ([eventStore saveEvent:event span:EKSpanThisEvent commit:FALSE error:&saveEventError])
                     {
                         NSLog(@"Event saved %@", [NSString stringWithFormat:@"%@ %@", [[planetaryHour objectForKey:@(Symbol)] string], [planetaryHour objectForKey:@(Name)]]);
                     } else {
                         NSLog(@"Error saving event: %@", saveEventError.description);
                     }
                 }
                 planetaryHoursCompletionBlock:^(NSArray<NSDictionary<NSNumber *,NSDate *> *> * _Nonnull planetaryHours) {
                     NSLog(@"Day %d", dayCounter++);
                 }
                 planetaryHourDataSourceCompletionBlock:^(NSError * _Nullable error) {
                     __autoreleasing NSError *saveEventsError;
                     if ([eventStore commit:&saveEventsError])
                     {
                         NSLog(@"Events saved to event store");
                     } else {
                         NSLog(@"Error saving events: %@", saveEventsError.description);
                     }
                 }];
            }
        } else {
            NSLog(@"Access to event store denied: %@", error.description);
        }
    }];
    
    
}

@end
