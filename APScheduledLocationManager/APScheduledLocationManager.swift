//
//  Created by Aleksandrs Proskurins
//
//  License
//  Copyright © 2016 Aleksandrs Proskurins
//  Released under an MIT license: http://opensource.org/licenses/MIT
//

import Foundation
import CoreLocation


public protocol APScheduledLocationManagerDelegate {
    
    func scheduledLocationManager(_ manager: APScheduledLocationManager, didFailWithError error: Error)
    func scheduledLocationManager(_ manager: APScheduledLocationManager, didUpdateLocations locations: [CLLocation])
    func scheduledLocationManager(_ manager: APScheduledLocationManager, didChangeAuthorization status: CLAuthorizationStatus)
}


public class APScheduledLocationManager: NSObject, CLLocationManagerDelegate {
    
    private let MaxBGTime: TimeInterval = 170
    private let MinBGTime: TimeInterval = 2
    private let MinAcceptableLocationAccuracy: CLLocationAccuracy = 5
    private let WaitForLocationsTime: TimeInterval = 3
    
    private let delegate: APScheduledLocationManagerDelegate
    private let manager = CLLocationManager()
    
    private var isManagerRunning = false
    private var checkLocationTimer: Timer?
    private var waitTimer: Timer?
    private var bgTask: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    private var lastLocations = [CLLocation]()
    
    public private(set) var acceptableLocationAccuracy: CLLocationAccuracy = 100
    public private(set) var checkLocationInterval: TimeInterval = 10
    public private(set) var isRunning = false
    
    public init(delegate: APScheduledLocationManagerDelegate) {
       
        self.delegate = delegate
        
        super.init()
        
        configureLocationManager()
    }
    
    private func configureLocationManager(){
        
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.delegate = self
    }
    
    public func requestAlwaysAuthorization() {
        
        manager.requestAlwaysAuthorization()
    }
    
    public func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
    
    public func startUpdatingLocation(interval: TimeInterval, acceptableLocationAccuracy: CLLocationAccuracy = 100) {
        
        if isRunning {
            
            stopUpdatingLocation()
        }
        
        checkLocationInterval -= WaitForLocationsTime
        checkLocationInterval = interval > MaxBGTime ? MaxBGTime : interval
        checkLocationInterval = interval < MinBGTime ? MinBGTime : interval
        
        self.acceptableLocationAccuracy = acceptableLocationAccuracy < MinAcceptableLocationAccuracy ? MinAcceptableLocationAccuracy : acceptableLocationAccuracy
        
        isRunning = true
        
        addNotifications()
        startLocationManager()
    }
    
    public func stopUpdatingLocation() {
        
        isRunning = false
        
        stopWaitTimer()
        stopLocationManager()
        stopBackgroundTask()
        stopCheckLocationTimer()
        removeNotifications()
    }
    
    private func addNotifications() {
        
        removeNotifications()
        
        NotificationCenter.default.addObserver(self, selector:  #selector(applicationDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector:  #selector(applicationDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    private func removeNotifications() {
        
        NotificationCenter.default.removeObserver(self)
    }
    
    private func startLocationManager() {
        
        isManagerRunning = true
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.startUpdatingLocation()
    }
    
    private func pauseLocationManager() {
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 99999
    }
    
    private func stopLocationManager() {
        
        isManagerRunning = false
        manager.stopUpdatingLocation()
    }
    
    @objc func applicationDidEnterBackground() {
        
        stopBackgroundTask()
        startBackgroundTask()
    }
    
    @objc func applicationDidBecomeActive() {
        
        stopBackgroundTask()
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    
        delegate.scheduledLocationManager(self, didChangeAuthorization: status)
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        
        delegate.scheduledLocationManager(self, didFailWithError: error)
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        guard isManagerRunning else { return }
        guard locations.count>0 else { return }
        
        lastLocations = locations
        
        if waitTimer == nil {
            startWaitTimer()
        }
    }
    
    private func startCheckLocationTimer() {
        
        stopCheckLocationTimer()
        
        checkLocationTimer = Timer.scheduledTimer(timeInterval: checkLocationInterval, target: self, selector: #selector(checkLocationTimerEvent), userInfo: nil, repeats: false)
    }
    
    private func stopCheckLocationTimer() {
        
        if let timer = checkLocationTimer {

            timer.invalidate()
            checkLocationTimer=nil
        }
    }
    
    @objc func checkLocationTimerEvent() {

        stopCheckLocationTimer()
        
        startLocationManager()
        
        // starting from iOS 7 and above stop background task with delay, otherwise location service won't start
        self.perform(#selector(stopAndResetBgTaskIfNeeded), with: nil, afterDelay: 1)
    }
    
    private func startWaitTimer() {
        stopWaitTimer()
    
        waitTimer = Timer.scheduledTimer(timeInterval: WaitForLocationsTime, target: self, selector: #selector(waitTimerEvent), userInfo: nil, repeats: false)
    }
    
    private func stopWaitTimer() {
        
        if let timer = waitTimer {
            
            timer.invalidate()
            waitTimer=nil
        }
    }
    
    @objc func waitTimerEvent() {
        
        stopWaitTimer()
        
        if acceptableLocationAccuracyRetrieved() {
            
            startBackgroundTask()
            startCheckLocationTimer()
            pauseLocationManager()
            
            delegate.scheduledLocationManager(self, didUpdateLocations: lastLocations)
        }else{
            
            startWaitTimer()
        }
    }
    
    private func acceptableLocationAccuracyRetrieved() -> Bool {
        
        guard let location = lastLocations.last else { return false }
        
        return location.horizontalAccuracy <= acceptableLocationAccuracy ? true : false
    }
   
    @objc func stopAndResetBgTaskIfNeeded()  {
        
        if isManagerRunning {
            stopBackgroundTask()
        }else{
            stopBackgroundTask()
            startBackgroundTask()
        }
    }
    
    private func startBackgroundTask() {
        let state = UIApplication.shared.applicationState
        
        if ((state == .background || state == .inactive) && bgTask == UIBackgroundTaskIdentifier.invalid) {
            
            bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                
                self.checkLocationTimerEvent()
            })
        }
    }
    
    @objc private func stopBackgroundTask() {
        guard bgTask != UIBackgroundTaskIdentifier.invalid else { return }
        
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = UIBackgroundTaskIdentifier.invalid
    }
}
