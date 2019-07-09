//
//  ViewController.m
//  JABPlanetaryHourCalendar
//
//  Created by Xcode Developer on 4/21/19.
//  Copyright © 2019 The Life of a Demoniac. All rights reserved.
//

#import "ViewController.h"
#import <CoreMedia/CoreMedia.h>

typedef NS_ENUM(NSUInteger, LogTextAttributes) {
    LogTextAttributes_Error,
    LogTextAttributes_Success,
    LogTextAttributes_Operation,
    LogTextAttributes_Event
};

@interface ViewController ()
{
    dispatch_queue_t loggerQueue;
    dispatch_queue_t taskQueue;
    NSDictionary *_eventTextAttributes, *_operationTextAttributes, *_errorTextAttributes, *_successTextAttributes;
    
    __block EKEventStore *eventStore;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"%s", __PRETTY_FUNCTION__);
    [self textStyles];
    
    [[PlanetaryHourGPUCalculator calculation] setPlanetaryHourDataSourceDelegate:(id<PlanetaryHourDataSourceLogDelegate> _Nullable)self];
    
    loggerQueue = dispatch_queue_create_with_target("Logger queue", DISPATCH_QUEUE_SERIAL, dispatch_get_main_queue());
    taskQueue = dispatch_queue_create_with_target("Task queue", DISPATCH_QUEUE_SERIAL, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    
    eventStore = [[EKEventStore alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(calendarPlanetaryHours) name:@"PlanetaryHoursDataSourceUpdatedNotification" object:nil];
//    [PlanetaryHourDataSource.data.locationManager requestLocation];
    [[PlanetaryHourDataSource data] setPlanetaryHourDataSourceDelegate:(id<PlanetaryHourDataSourceLogDelegate> _Nullable)self];
}


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
    [self log:@"JABPlanetaryHourFramework" entry:@"Received GPS location data" time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Event];
    [self log:@"EventKit" entry:@"Requesting access to Calendar event store..." time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Operation];
    [eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError * _Nullable error) {
        if (granted)
        {
            [self log:@"EventKit" entry:@"Access to Calendar granted" time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Success];
            
            // Remove any existing Planetary Hours calendar
            NSArray <EKCalendar *> *calendars = [self->eventStore calendarsForEntityType:EKEntityTypeEvent];
            [calendars enumerateObjectsUsingBlock:^(EKCalendar * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                [self log:@"EventKit" entry:[NSString stringWithFormat:@"Found %@ calendar...", obj.title] time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Event];
                
                // TO-DO: Remove condition that a planetary hour calendar must exist in order to add new planetary hour events
                if ([obj.title isEqualToString:@"Planetary Hour"]) {
                    [self log:@"EventKit" entry:@"Removing existing Planetary Hour calendar..." time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Operation];
                    
                    *stop = TRUE;
                    __autoreleasing NSError *error;
                    if ([self->eventStore removeCalendar:obj commit:TRUE error:&error])
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self log:@"EventKit" entry:@"Planetary hour calendar removed." time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Success];
                            
                            __autoreleasing NSError *removeOldCalendarError;
                            if ([self->eventStore saveCalendar:obj commit:TRUE error:&removeOldCalendarError])
                                [self log:@"EventKit" entry:@"Changes saved to Calendar" time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Success];
                            else
                                [self log:@"JABPlanetaryHourFramework" entry:[NSString stringWithFormat:@"Error saving changes to event store:\t%@", removeOldCalendarError.description] time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Error];
                        });
                    else
                        [self log:@"JABPlanetaryHourFramework" entry:[NSString stringWithFormat:@"Error removing planetary hour calendar:/t%@", error.description] time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Error];
                    // TO-DO: a new calendar should not be created with new planetary hours if the existing one camnot be deleted
                }

            }];
            
            __block EKCalendar *calendar = [EKCalendar calendarForEntityType:EKEntityTypeEvent eventStore:self->eventStore];
            calendar.title = @"Planetary Hour";
            calendar.source = self->eventStore.sources[1];
            __autoreleasing NSError *error;
            if ([self->eventStore saveCalendar:calendar commit:TRUE error:&error])
            {
                if (error)
                {
                    [self log:@"EventKit" entry:[NSString stringWithFormat:@"Error creating new planetary hour calendar: %@\nCreating a default calendar for new planetary hour events...", error.localizedDescription] time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Error];
                    calendar = [self->eventStore defaultCalendarForNewEvents];
                } else {
                    [self log:@"EventKit" entry:@"New planetary hour calendar created..." time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Success];
                    
                }
                
                [self log:@"JABPlanetaryHourFramework" entry:@"Adding planetary hours to the Planetary Hour calendar..." time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Operation];
                NSRange days = NSMakeRange(0, 356);
                NSRange hours = NSMakeRange(0, 24);
                NSIndexSet *daysIndices  = [[NSIndexSet alloc] initWithIndexesInRange:days];      // Calendar one year of events, starting today
                NSMutableIndexSet *dataIndices  = [[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, 4)];
                [dataIndices addIndex:6];                                                                       // Return 0-4 and  indices of planetary hour data
                NSIndexSet *hoursIndices = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, 24)];      // Generate data for each planetary hour of the day
                CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(PlanetaryHourDataSource.data.locationManager.location.coordinate.latitude, PlanetaryHourDataSource.data.locationManager.location.coordinate.longitude);
                [PlanetaryHourDataSource.data solarCyclesForDays:daysIndices planetaryHourData:dataIndices planetaryHours:hoursIndices
                                       solarCycleCompletionBlock:nil
                                    planetaryHourCompletionBlock:^(NSDictionary<NSNumber *,id> * _Nonnull planetaryHour) {
                                        [self->eventStore saveEvent:planetaryHourEvent(self->eventStore, calendar, planetaryHour, coordinate) span:EKSpanThisEvent commit:FALSE error:nil];
                                    } planetaryHoursCompletionBlock:^(NSArray<NSDictionary<NSNumber *,NSDate *> *> * _Nonnull planetaryHours) {
                                        if ([self->eventStore commit:nil])
                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                [self.datePicker setDate:[planetaryHours[0] objectForKey:@(StartDate)]];
                                            });
                                    } planetaryHourDataSourceCompletionBlock:^(NSError * _Nullable error) {
                                        if (error)
                                            [self log:@"JABPlanetaryHourFramework" entry:error.description time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Error];
                                        else
                                            [self log:@"JABPlanetaryHourFramework" entry:[NSString stringWithFormat:@"%d planetary hours added to the Planetary Hour calendar", days.length * hours.length] time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Success];
                                        
                                        if ([self->eventStore saveCalendar:calendar commit:TRUE error:nil])
                                            [self log:@"JABPlanetaryHourFramework" entry:@"New planetary hour calendar saved." time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Success];
                                        else
                                            [self log:@"JABPlanetaryHourFramework" entry:@"Error saving new planetary hour calendar." time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Error];
                                    }];
            }
            
        } else {
            [self log:@"JABPlanetaryHourFramework" entry:[NSString stringWithFormat:@"Access to Calendar denied: %@", error.description] time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:LogTextAttributes_Error];
        }
    }];
    
    
    //
    //        });
    //    }
    //     }];
    
    
    //}];
}

- (void)textStyles
{
    NSMutableParagraphStyle *leftAlignedParagraphStyle = [[NSMutableParagraphStyle alloc] init];
    leftAlignedParagraphStyle.alignment = NSTextAlignmentLeft;
    _operationTextAttributes = @{NSForegroundColorAttributeName: [UIColor colorWithRed:0.87 green:0.5 blue:0.0 alpha:1.0],
                                 NSFontAttributeName: [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium]};
    
    NSMutableParagraphStyle *fullJustificationParagraphStyle = [[NSMutableParagraphStyle alloc] init];
    fullJustificationParagraphStyle.alignment = NSTextAlignmentJustified;
    _errorTextAttributes = @{NSForegroundColorAttributeName: [UIColor colorWithRed:0.91 green:0.28 blue:0.5 alpha:1.0],
                             NSFontAttributeName: [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium]};
    
    NSMutableParagraphStyle *rightAlignedParagraphStyle = [[NSMutableParagraphStyle alloc] init];
    rightAlignedParagraphStyle.alignment = NSTextAlignmentRight;
    _eventTextAttributes = @{NSForegroundColorAttributeName: [UIColor colorWithRed:0.0 green:0.54 blue:0.87 alpha:1.0],
                             NSFontAttributeName: [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium],
                             NSParagraphStyleAttributeName: rightAlignedParagraphStyle};
    
    NSMutableParagraphStyle *centerAlignedParagraphStyle = [[NSMutableParagraphStyle alloc] init];
    centerAlignedParagraphStyle.alignment = NSTextAlignmentCenter;
    _successTextAttributes = @{NSForegroundColorAttributeName: [UIColor colorWithRed:0.0 green:0.87 blue:0.19 alpha:1.0],
                               NSFontAttributeName: [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium],
                               NSParagraphStyleAttributeName: rightAlignedParagraphStyle}; // cnanged to right-aligned
}

static NSString *stringFromCMTime(CMTime time)
{
    NSString *stringFromCMTime;
    float seconds = round(CMTimeGetSeconds(time));
    int hh = (int)floorf(seconds / 3600.0f);
    int mm = (int)floorf((seconds - hh * 3600.0f) / 60.0f);
    int ss = (((int)seconds) % 60);
    if (hh > 0)
    {
        stringFromCMTime = [NSString stringWithFormat:@"%02d:%02d:%02d", hh, mm, ss];
    }
    else
    {
        stringFromCMTime = [NSString stringWithFormat:@"%02d:%02d", mm, ss];
    }
    return stringFromCMTime;
}

- (void)log:(NSString *)context entry:(NSString *)entry status:(LogEntryType)type
{
    [self log:context entry:entry time:CMClockGetTime(CMClockGetHostTimeClock()) textAttributes:(LogTextAttributes)type];
}

- (void)log:(NSString *)context entry:(NSString *)entry time:(CMTime)time textAttributes:(NSUInteger)logTextAttributes
{
    NSDictionary *attributes;
    switch (logTextAttributes) {
        case LogTextAttributes_Event:
            attributes = _eventTextAttributes;
            break;
        case LogTextAttributes_Operation:
            attributes = _operationTextAttributes;
            break;
        case LogTextAttributes_Success:
            attributes = _successTextAttributes;
            break;
        case LogTextAttributes_Error:
            attributes = _errorTextAttributes;
            break;
        default:
            attributes = _errorTextAttributes;
            break;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        //        [self displayYHeightForFrameBoundsRect:CGRectMake(self.eventLogTextView.frame.origin.y, self.eventLogTextView.frame.size.height, self.eventLogTextView.bounds.origin.y, self.eventLogTextView.bounds.size.height)
        //         withLabel:@"START"];
        NSMutableAttributedString *log = [[NSMutableAttributedString alloc] initWithAttributedString:[self.eventLogTextView attributedText]];
        NSAttributedString *time_s = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n\n%@", stringFromCMTime(time)] attributes:attributes];
        NSAttributedString *context_s = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@", context] attributes:attributes];
        NSAttributedString *entry_s = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@", entry] attributes:attributes];
        [log appendAttributedString:time_s];
        [log appendAttributedString:context_s];
        [log appendAttributedString:entry_s];
        [self.eventLogTextView setAttributedText:log];
        
        //        CGRect rect = [self.eventLogTextView firstRectForRange:[self.eventLogTextView textRangeFromPosition:self.eventLogTextView.beginningOfDocument toPosition:self.eventLogTextView.endOfDocument]];
        //        [self displayYHeightForFrameBoundsRect:CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height) withLabel:@"First rect for range"];
        //        CGFloat heightDifference = rect.size.height - self.eventLogTextView.bounds.size.height;
        //        NSLog(@"heightDifference\t%f", heightDifference);
        //        CGRect visibleRect = CGRectMake(rect.origin.x, rect.origin.y + heightDifference, rect.size.width, rect.size.height);
        ////        [self displayYHeightForFrameBoundsRect:CGRectMake(visibleRect.origin.x, visibleRect.origin.y, visibleRect.size.width, visibleRect.size.height) withLabel:@"Visible rect"];
        //        if (heightDifference > 0)
        //        {
        //            CGRect newRect = CGRectMake(0, heightDifference, visibleRect.size.width, self.eventLogTextView.bounds.size.height);
        //            [self.eventLogTextView scrollRectToVisible:newRect animated:TRUE];
        ////            NSLog(@"New rect\tx: %f, y: %f, w: %f, h: %f\n\n", newRect.origin.x, newRect.origin.y, newRect.size.width, newRect.size.height);
        //        }
        ////        [self displayYHeightForFrameBoundsRect:CGRectMake(self.eventLogTextView.frame.origin.y, self.eventLogTextView.frame.size.height, self.eventLogTextView.bounds.origin.y, self.eventLogTextView.bounds.size.height) withLabel:@"END\n\n"];
    });
}
- (IBAction)toggleToneGenerator:(UITapGestureRecognizer *)sender {
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





