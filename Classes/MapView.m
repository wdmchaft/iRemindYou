//
//  MapViewController.m
//
//

#import "MapView.h"

@interface MapView()

-(NSMutableArray *)decodePolyLine: (NSMutableString *)encoded;
-(void) updateRouteView;
-(NSArray*) calculateRoutesFrom:(CLLocationCoordinate2D) from to: (CLLocationCoordinate2D) to;
-(void) centerMap;

@end

@implementation MapView

@synthesize lineColor, mapView, placeStore, canRouting;

- (id) initWithFrame:(CGRect) frame
{
	self = [super initWithFrame:frame];
	if (self != nil) {
        mapView = [[MKMapView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
		mapView.showsUserLocation = YES;
        [mapView setDelegate:self];
		[self addSubview:mapView];
		routeView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, mapView.frame.size.width, mapView.frame.size.height)];
		routeView.userInteractionEnabled = NO;
		[mapView addSubview:routeView];
		
		self.lineColor = [UIColor colorWithWhite:0.2 alpha:0.5];

        UILongPressGestureRecognizer *lpgr = [[UILongPressGestureRecognizer alloc] 
                                              initWithTarget:self action:@selector(handleLongPress:)];
        lpgr.minimumPressDuration = 1.0; //user needs to press for 1 seconds
        [mapView addGestureRecognizer:lpgr];
        [lpgr release];

        placeStore=[PlaceStore sharedPlaceStore];
        if (placeStore.placeList.count>0){
            Place * p;
            for (p in placeStore.placeList){
                PlaceMark * placeMark=[[[PlaceMark alloc] initWithPlace:p] autorelease];
                [mapView addAnnotation:placeMark];
            }
        }
        else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Welcome!" message:@"To add Event longpress to  map" delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
			[alert release];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addPlaceMark:) name:@"addPlaceMark" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removePlaceMark:) name:@"removePlaceMark" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(travelMode:) name:@"travelMode" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(gotoLocation:) name:@"gotoLocation" object:nil];
        
        [mapView.userLocation addObserver:self forKeyPath:@"location" options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld) context:nil];
             canRouting=YES;
        timeToPlace=0;
        travelMode=travelDriving;

	}
	return self;
}

// Listen to change in the userLocation
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context 
{       
    MKCoordinateRegion region;
    region.center = self.mapView.userLocation.coordinate;  
    
    MKCoordinateSpan span; 
    span.latitudeDelta  = 0.05; // Change these values to change the zoom
    span.longitudeDelta = 0.05; 
    region.span = span;
    [mapView.userLocation removeObserver:self forKeyPath:@"location"];
    
    [mapView setRegion:region animated:YES];
    
}

- (void)handleLongPress:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;
    
    CGPoint touchPoint = [gestureRecognizer locationInView:self.mapView];   
    CLLocationCoordinate2D touchMapCoordinate = 
    [self.mapView convertPoint:touchPoint toCoordinateFromView:self.mapView];
    
    
    Place* place = [[[Place alloc] init] autorelease];
    place.latitude=touchMapCoordinate.latitude;
    place.longitude=touchMapCoordinate.longitude;
    
    [placeStore addPlace:place];
}

#pragma mark -
#pragma mark Methods for working with PlaceStore

-(PlaceMark *) PlaceMarkByPlace:(Place *) p
{
    PlaceMark *placeMark;
    for (placeMark in [mapView annotations]){
        if ([placeMark respondsToSelector:@selector(place)] && p==placeMark.place){
            return placeMark;
            break;
        }
    }
    return nil;
}

-(void) addPlaceMark:(NSNotification *)notification {
    Place * place=[[notification object]retain];
    if (place){
        PlaceMark *placeMark=[[[PlaceMark alloc]initWithPlace:place]autorelease];
        [mapView addAnnotation:placeMark];
    }
}

-(void) updatePlaceMark:(NSNotification *)notification {
    Place * place=[notification object];
    if (place){
        PlaceMark *placeMark=[self PlaceMarkByPlace:place];
        [mapView removeAnnotation:placeMark]; 
        [mapView addAnnotation:placeMark]; 
    }
}

-(void) removePlaceMark:(NSNotification *)notification {
    Place * place=[notification object];
    if (place){
        PlaceMark *placeMark=[self PlaceMarkByPlace:place];
        [mapView removeAnnotation:placeMark];
    }
}

-(void) travelMode:(NSNotification *)notification {
    NSNumber* number=[notification object];
    travelMode=[number intValue];
    NSLog(@"Set travelmode: %d",travelMode);
    
}

-(void) gotoLocation:(NSNotification *)notification {
    
    NSLog(@"Set Location..");
   [mapView.userLocation addObserver:self forKeyPath:@"location" options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld) context:nil];
    
}

#pragma mark -
#pragma mark Working with routes

-(NSMutableArray *)decodePolyLine: (NSMutableString *)encoded {
	[encoded replaceOccurrencesOfString:@"\\\\" withString:@"\\"
								options:NSLiteralSearch
								  range:NSMakeRange(0, [encoded length])];
	NSInteger len = [encoded length];
	NSInteger index = 0;
	NSMutableArray *array = [[[NSMutableArray alloc] init] autorelease];
	NSInteger lat=0;
	NSInteger lng=0;
	while (index < len) {
		NSInteger b;
		NSInteger shift = 0;
		NSInteger result = 0;
		do {
			b = [encoded characterAtIndex:index++] - 63;
			result |= (b & 0x1f) << shift;
			shift += 5;
		} while (b >= 0x20);
		NSInteger dlat = ((result & 1) ? ~(result >> 1) : (result >> 1));
		lat += dlat;
		shift = 0;
		result = 0;
		do {
			b = [encoded characterAtIndex:index++] - 63;
			result |= (b & 0x1f) << shift;
			shift += 5;
		} while (b >= 0x20);
		NSInteger dlng = ((result & 1) ? ~(result >> 1) : (result >> 1));
		lng += dlng;
		NSNumber *latitude = [[[NSNumber alloc] initWithFloat:lat * 1e-5] autorelease];
		NSNumber *longitude = [[[NSNumber alloc] initWithFloat:lng * 1e-5] autorelease];
		printf("[%f,", [latitude doubleValue]);
		printf("%f]", [longitude doubleValue]);
		CLLocation *loc = [[[CLLocation alloc] initWithLatitude:[latitude floatValue] longitude:[longitude floatValue]] autorelease];
		[array addObject:loc];
	}
	
	return array;
}
-(NSNumber*) timeStrToNum:(NSString *) time;
{
    int secs=0; 
    int mins=0; 
    int hours=0; 
    
    
    NSString *str=time;
    NSString *strHours;
    NSString *strMins;
    NSString *strSecs;
    
    NSRange rangeHours=[str rangeOfString:@"hours"];
    
    if(rangeHours.location == NSNotFound)
    { 
        rangeHours=[str rangeOfString:@"hour"];
        if(rangeHours.location == NSNotFound)
        { 
            rangeHours=[str rangeOfString:@"ч."];
        }
        
    }
    if (rangeHours.location != NSNotFound){
        strHours=[str substringToIndex:rangeHours.location-1];
        hours=[strHours integerValue];
        str=[str substringFromIndex:(rangeHours.location+rangeHours.length)];
    }
    
    NSRange rangeMins=[str rangeOfString:@"mins"];
    
    if(rangeMins.location == NSNotFound)
    { 
        rangeMins=[str rangeOfString:@"min"];
        if(rangeMins.location == NSNotFound)
        { 
            rangeMins=[str rangeOfString:@"мин."];
        }
    }
    
    if (rangeMins.location != NSNotFound){
        strMins=[str substringToIndex:rangeMins.location-1];
        mins=[strMins integerValue];
        str=[str substringFromIndex:(rangeMins.location+rangeMins.length)];
        
    }
   
    NSRange rangeSecs=[str rangeOfString:@"secs"];    
    if(rangeSecs.location == NSNotFound)
    { 
        rangeSecs=[str rangeOfString:@"sec"];
        if(rangeSecs.location == NSNotFound)
        { 
            rangeSecs=[str rangeOfString:@"сек."];
        }
    }
    
    if (rangeSecs.location != NSNotFound){
        strSecs=[str substringToIndex:rangeSecs.location-1];
        secs=[strSecs integerValue];
    }
    secs=secs+mins*60+hours*3600;
    return [NSNumber numberWithInteger:(secs)];
}

-(NSArray*) calculateRoutesFrom:(CLLocationCoordinate2D) f to: (CLLocationCoordinate2D) t {
	NSString* saddr = [NSString stringWithFormat:@"%f,%f", f.latitude, f.longitude];
	NSString* daddr = [NSString stringWithFormat:@"%f,%f", t.latitude, t.longitude];
	NSString* strTravelMode;
    switch (travelMode) {
        case travelDriving:
            strTravelMode=@"Driving";
            break;
        case travelWalking:
            strTravelMode=@"Walking";
            break;
        case travelBicykling:
            strTravelMode=@"Bicycling";
            break;
        default:
            break;
    } 
    
	NSString* apiUrlStr = [NSString stringWithFormat:@"http://maps.google.com/maps?output=dragdir&saddr=%@&daddr=%@&mode=%@", saddr, daddr,strTravelMode];
	NSURL* apiUrl = [NSURL URLWithString:apiUrlStr];
	NSLog(@"api url: %@", apiUrl);
	NSString *apiResponse = [NSString stringWithContentsOfURL:apiUrl];
    strTimeToPlace=[apiResponse stringByMatching:@"tooltipHtml:\\\"([^\\\"]*)"];
    NSRange range=[strTimeToPlace rangeOfString:@"\\x26#160;"];

    if (strTimeToPlace){
        strTimeToPlace=[strTimeToPlace stringByReplacingCharactersInRange:range withString:@" "];
        range=[strTimeToPlace rangeOfString:@"tooltipHtml:\" "];
        strTimeToPlace=[strTimeToPlace stringByReplacingCharactersInRange:range withString:@""];
        range=[strTimeToPlace rangeOfString:@"/ "];
        NSString *time=[strTimeToPlace substringFromIndex:range.location+2];
        NSLog(@"strTimeToPlace: %@", strTimeToPlace);
        timeToPlace=[self timeStrToNum:time];
        NSLog(@"timeToPlace: %@", timeToPlace);
    }
    NSString* encodedPoints = [apiResponse stringByMatching:@"points:\\\"([^\\\"]*)\\\"" capture:1L];
	return [self decodePolyLine:[[encodedPoints mutableCopy]autorelease]];
}

-(void) calculateTimeFrom:(Place *) f to: (Place *) t;
{
	NSString* saddr = [NSString stringWithFormat:@"%f,%f", f.latitude, f.longitude];
	NSString* daddr = [NSString stringWithFormat:@"%f,%f", t.latitude, t.longitude];
	
	NSString* apiUrlStr = [NSString stringWithFormat:@"http://maps.google.com/maps?output=dragdir&saddr=%@&daddr=%@", saddr, daddr];
	NSURL* apiUrl = [NSURL URLWithString:apiUrlStr];
	NSLog(@"api url: %@", apiUrl);
	NSString *apiResponse = [NSString stringWithContentsOfURL:apiUrl];
    strTimeToPlace=[apiResponse stringByMatching:@"tooltipHtml:\\\"([^\\\"]*)"];
    NSRange range=[strTimeToPlace rangeOfString:@"\\x26#160;"];
    
    if (strTimeToPlace){
        strTimeToPlace=[strTimeToPlace stringByReplacingCharactersInRange:range withString:@" "];
        range=[strTimeToPlace rangeOfString:@"tooltipHtml:\" "];
        strTimeToPlace=[strTimeToPlace stringByReplacingCharactersInRange:range withString:@""];
        range=[strTimeToPlace rangeOfString:@"/ "];
        NSString *time=[strTimeToPlace substringFromIndex:range.location+2];
        NSLog(@"strTimeToPlace: %@", strTimeToPlace);
        timeToPlace=[self timeStrToNum:time];
        NSLog(@"timeToPlace: %@", timeToPlace);
        t.timeToPlace=timeToPlace;
    }
}


-(void) centerMap {
	MKCoordinateRegion region;

	CLLocationDegrees maxLat = -90;
	CLLocationDegrees maxLon = -180;
	CLLocationDegrees minLat = 90;
	CLLocationDegrees minLon = 180;
	for(int idx = 0; idx < routes.count; idx++)
	{
		CLLocation* currentLocation = [routes objectAtIndex:idx];
		if(currentLocation.coordinate.latitude > maxLat)
			maxLat = currentLocation.coordinate.latitude;
		if(currentLocation.coordinate.latitude < minLat)
			minLat = currentLocation.coordinate.latitude;
		if(currentLocation.coordinate.longitude > maxLon)
			maxLon = currentLocation.coordinate.longitude;
		if(currentLocation.coordinate.longitude < minLon)
			minLon = currentLocation.coordinate.longitude;
	}
	region.center.latitude     = (maxLat + minLat) / 2;
	region.center.longitude    = (maxLon + minLon) / 2;
	region.span.latitudeDelta  = maxLat - minLat;
	region.span.longitudeDelta = maxLon - minLon;
	
	[mapView setRegion:region animated:YES];
}

-(void) showRouteFrom: (Place*) f to:(Place*) t {
	canRouting=NO;
    if(routes) {
		[routes release];
        [mapView removeOverlays:[mapView overlays]];
	}
	
	PlaceMark* from = [[[PlaceMark alloc] initWithPlace:f] autorelease];
	PlaceMark* to = [self PlaceMarkByPlace:t];
    if (to && f && t)
    {
        routes = [[self calculateRoutesFrom:from.coordinate to:to.coordinate] retain];
        
        [self updateRouteView];
//        [self centerMap];
        if (strTimeToPlace){
            if (t.event.notes){
                t.description=[strTimeToPlace stringByAppendingString: t.event.notes];
            }
            else{
                t.description=strTimeToPlace;
            }
            t.timeToPlace=timeToPlace;
            NSLog(@"time: %@ to place: %@",timeToPlace, t);
    }
        [mapView addAnnotation:to];
    }    
    canRouting=YES;
}

-(void) updateRouteView {

    CLLocationCoordinate2D mapCoords[routes.count];
    for(int i = 0; i < routes.count; i++) {
        CLLocation* location = [routes objectAtIndex:i];
        mapCoords[i] =location.coordinate; 
    }
    
    MKPolyline *polyLine = [MKPolyline polylineWithCoordinates:mapCoords count:routes.count];
    [mapView addOverlay:polyLine];
    [mapView setDelegate:self];
        
    
}

- (MKOverlayView *)mapView:(MKMapView *)mapView viewForOverlay:(id <MKOverlay>)overlay
{
    MKPolylineView *polylineView = [[[MKPolylineView alloc] initWithOverlay:overlay] autorelease];
    polylineView.strokeColor = [UIColor blueColor];
    polylineView.lineWidth = 2.0;
    polylineView.alpha=0.5;
    return polylineView;
}

#pragma mark mapView delegate functions
- (void)mapView:(MKMapView *)mapView regionWillChangeAnimated:(BOOL)animated
{
	routeView.hidden = YES;
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
	[self updateRouteView];
	routeView.hidden = NO;
	[routeView setNeedsDisplay];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation {
    
    MKPinAnnotationView *view = nil; // return nil for the current user location
    
    if (annotation != self.mapView.userLocation) {
        
        view = (MKPinAnnotationView *)[self.mapView dequeueReusableAnnotationViewWithIdentifier:@"identifier"];
        
        if (nil == view) {
            view = [[[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"identifier"] autorelease];
            view.rightCalloutAccessoryView = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        }
        
        [view setPinColor:MKPinAnnotationColorPurple];
        [view setCanShowCallout:YES];
        [view setAnimatesDrop:YES];
        [view setDraggable:YES];
        
    }
    return view;
}

-(void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view didChangeDragState:(MKAnnotationViewDragState)newState fromOldState:(MKAnnotationViewDragState)oldState {
    if (oldState == MKAnnotationViewDragStateDragging) {
        
    }
    if (newState == MKAnnotationViewDragStateEnding) {
        PlaceMark *placeMark=view.annotation;
        Place *p=placeMark.place;
        [placeStore updatePlace:p];
    }
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control {
    NSLog(@"%@",[view.annotation description]);
    PlaceMark *placeMark=view.annotation;
    [placeStore editPlace:placeMark.place];
}

- (void)dealloc {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"addPlaceMark" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"removePlaceMark" object:nil];
    
	if(routes) {
		[routes release];
	}
	[mapView release];
	[routeView release];
    [super dealloc];
}

#pragma mark -
#pragma mark UIAlertViewDelegate Methods

// Called when an alert button is tapped.
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if(buttonIndex > 0) {
		travelMode = buttonIndex; 
	}
    
}



@end
