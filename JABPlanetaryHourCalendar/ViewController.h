//
//  ViewController.h
//  JABPlanetaryHourCalendar
//
//  Created by Xcode Developer on 4/21/19.
//  Copyright © 2019 The Life of a Demoniac. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <EventKit/EventKit.h>
#import <JABPlanetaryHourCocoaTouchFramework/JABPlanetaryHourCocoaTouchFramework.h>

@interface ViewController : UIViewController <PlanetaryHourDataSourceLogDelegate>

@property (weak, nonatomic) IBOutlet UIDatePicker *datePicker;
@property (weak, nonatomic) IBOutlet UITextView *eventLogTextView;

- (void)log:(NSString *)context entry:(NSString *)entry status:(LogEntryType)type;

@end

