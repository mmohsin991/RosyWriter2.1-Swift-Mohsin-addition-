//
//  RosyWriterViewController.swift
//  RosyWriter
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/1/18.
//
//
//
/*
     File: RosyWriterViewController.h
     File: RosyWriterViewController.m
 Abstract: View controller for camera interface
  Version: 2.1

 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.

 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.

 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.

 Copyright (C) 2014 Apple Inc. All Rights Reserved.

 */


import UIKit
import AVFoundation



protocol MohsinProtocol{
    func filterImageBuffer(var sourceImage : CIImage) -> CIImage?
}



@objc(RosyWriterViewController)
class RosyWriterViewController: UIViewController, RosyWriterCapturePipelineDelegate, MohsinProtocol {
    
    private var _addedObservers: Bool = false
    private var _recording: Bool = false
    private var _backgroundRecordingID: UIBackgroundTaskIdentifier = 0
    private var _allowedToUseGPU: Bool = false
    
    @IBOutlet private var recordButton: UIBarButtonItem!
    @IBOutlet private var framerateLabel: UILabel!
    @IBOutlet private var dimensionsLabel: UILabel!
    private var labelTimer: NSTimer?
    private var previewView: OpenGLPixelBufferView?
    private var capturePipeline: RosyWriterCapturePipeline!
    
    deinit {
        if _addedObservers {
            NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidEnterBackgroundNotification, object: UIApplication.sharedApplication())
            NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillEnterForegroundNotification, object: UIApplication.sharedApplication())
            NSNotificationCenter.defaultCenter().removeObserver(self, name: UIDeviceOrientationDidChangeNotification, object: UIDevice.currentDevice())
            UIDevice.currentDevice().endGeneratingDeviceOrientationNotifications()
        }
        
    }
    
    //MARK: - View lifecycle
    
    func applicationDidEnterBackground() {
        // Avoid using the GPU in the background
        _allowedToUseGPU = false
        self.capturePipeline?.renderingEnabled = false
        
        self.capturePipeline?.stopRecording() // no-op if we aren't recording
        
        // We reset the OpenGLPixelBufferView to ensure all resources have been clear when going to the background.
        self.previewView?.reset()
    }
    
    func applicationWillEnterForeground() {
        _allowedToUseGPU = true
        self.capturePipeline?.renderingEnabled = true
    }
    
    override func viewDidLoad() {
        let rosyWriterCapturePipeline = RosyWriterCapturePipeline(delegateMohsin: self)
        
        self.capturePipeline = rosyWriterCapturePipeline
        
        
        self.capturePipeline.setDelegate(self, callbackQueue: dispatch_get_main_queue())
        
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: "applicationDidEnterBackground",
            name: UIApplicationDidEnterBackgroundNotification,
            object: UIApplication.sharedApplication())
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: "applicationWillEnterForeground",
            name: UIApplicationWillEnterForegroundNotification,
            object: UIApplication.sharedApplication())
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: "deviceOrientationDidChange",
            name: UIDeviceOrientationDidChangeNotification,
            object: UIDevice.currentDevice())
        
        // Keep track of changes to the device orientation so we can update the capture pipeline
        UIDevice.currentDevice().beginGeneratingDeviceOrientationNotifications()
        
        _addedObservers = true
        
        // the willEnterForeground and didEnterBackground notifications are subsequently used to update _allowedToUseGPU
        _allowedToUseGPU = (UIApplication.sharedApplication().applicationState != .Background)
        self.capturePipeline.renderingEnabled = _allowedToUseGPU
        
        super.viewDidLoad()
        
        
        
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        self.capturePipeline.startRunning()
        
        self.labelTimer = NSTimer.scheduledTimerWithTimeInterval(0.5, target: self, selector: "updateLabels", userInfo: nil, repeats: true)
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        
        self.labelTimer?.invalidate()
        self.labelTimer = nil
        
        self.capturePipeline.stopRunning()
    }
    
    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.Portrait
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    

    
    
    //MARK: - UI
    
    @IBAction func toggleRecording(_: AnyObject) {
        if _recording {
            self.capturePipeline.stopRecording()
        } else {
            // Disable the idle timer while recording
            UIApplication.sharedApplication().idleTimerDisabled = true
            
            // Make sure we have time to finish saving the movie if the app is backgrounded during recording
            if UIDevice.currentDevice().multitaskingSupported {
                _backgroundRecordingID = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler({})
            }
            
            self.recordButton.enabled = false; // re-enabled once recording has finished starting
            self.recordButton.title = "Stop"
            
            self.capturePipeline.startRecording()
            
            _recording = true
        }
    }
    
    private func recordingStopped() {
        _recording = false
        self.recordButton.enabled = true
        self.recordButton.title = "Record"
        
        UIApplication.sharedApplication().idleTimerDisabled = false
        
        UIApplication.sharedApplication().endBackgroundTask(_backgroundRecordingID)
        _backgroundRecordingID = UIBackgroundTaskInvalid
    }
    
    private func setupPreviewView() {
        // Set up GL view
        self.previewView = OpenGLPixelBufferView(frame: CGRectZero)
        self.previewView!.autoresizingMask = [UIViewAutoresizing.FlexibleHeight, UIViewAutoresizing.FlexibleWidth]
        
        let currentInterfaceOrientation = UIApplication.sharedApplication().statusBarOrientation
        self.previewView!.transform = self.capturePipeline.transformFromVideoBufferOrientationToOrientation(AVCaptureVideoOrientation(rawValue: currentInterfaceOrientation.rawValue)!, withAutoMirroring: true) // Front camera preview should be mirrored
        
        self.view.insertSubview(self.previewView!, atIndex: 0)
        var bounds = CGRectZero
        bounds.size = self.view.convertRect(self.view.bounds, toView: self.previewView).size
        self.previewView!.bounds = bounds
        self.previewView!.center = CGPointMake(self.view.bounds.size.width/2.0, self.view.bounds.size.height/2.0)
    }
    
    func deviceOrientationDidChange() {
        let deviceOrientation = UIDevice.currentDevice().orientation
        
        // Update recording orientation if device changes to portrait or landscape orientation (but not face up/down)
        if UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation) {
            self.capturePipeline.recordingOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue)!
        }
    }
    
    func updateLabels() {
        let frameRateString = "\(Int(roundf(self.capturePipeline.videoFrameRate))) FPS"
        self.framerateLabel.text = frameRateString
        
        let dimensionsString = "\(self.capturePipeline.videoDimensions.width) x \(self.capturePipeline.videoDimensions.height)"
        self.dimensionsLabel.text = dimensionsString
    }
    
    private func showError(error: NSError) {
        if #available(iOS 8.0, *) {
            let alert = UIAlertController(title: error.localizedDescription, message: error.localizedFailureReason, preferredStyle: .Alert)
            alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
            self.presentViewController(alert, animated: true, completion: nil)
        } else {
            let alertView = UIAlertView(title: error.localizedDescription,
                message: error.localizedFailureReason,
                delegate: nil,
                cancelButtonTitle: "OK")
            alertView.show()
        }
    }
    
    //MARK: - RosyWriterCapturePipelineDelegate
    
    func capturePipeline(capturePipeline: RosyWriterCapturePipeline, didStopRunningWithError error: NSError) {
        self.showError(error)
        
        self.recordButton.enabled = false
    }
    
    // Preview
    func capturePipeline(capturePipeline: RosyWriterCapturePipeline, previewPixelBufferReadyForDisplay previewPixelBuffer: CVPixelBuffer) {
        if !_allowedToUseGPU {
            return
        }
        if self.previewView == nil {
            self.setupPreviewView()
        }
        
        self.previewView!.displayPixelBuffer(previewPixelBuffer)
    }
    
    func capturePipelineDidRunOutOfPreviewBuffers(capturePipeline: RosyWriterCapturePipeline) {
        if _allowedToUseGPU {
            self.previewView?.flushPixelBufferCache()
        }
    }
    
    // Recording
    func capturePipelineRecordingDidStart(capturePipeline: RosyWriterCapturePipeline) {
        self.recordButton.enabled = true
    }
    
    func capturePipelineRecordingWillStop(capturePipeline: RosyWriterCapturePipeline) {
        // Disable record button until we are ready to start another recording
        self.recordButton.enabled = false
        self.recordButton.title = "Record"
    }
    
    func capturePipelineRecordingDidStop(capturePipeline: RosyWriterCapturePipeline) {
        self.recordingStopped()
    }
    
    func capturePipeline(capturePipeline: RosyWriterCapturePipeline, recordingDidFailWithError error: NSError) {
        self.recordingStopped()
        self.showError(error)
    }
    
    
    
    
    
    
    var filter = CIFilter(name: "CIStraightenFilter")!

    
    @IBAction func changeFilter(sender: UIButton) {
        
    // Mohsin
      self.filter = CIFilter(name: "CISepiaTone")!
        
        self.filter.setValue(0.5, forKey: kCIInputIntensityKey)

//        filter.setValue(CIVector(values: [0.2, 0.1, 0.2, 0], count: 4), forKey: "inputMinComponents")
//
//        filter.setValue(2.1, forKey: "inputShadowAmount")
        
//        self.capturePipeline._renderer.setRosyFilter(self.filter)

    
    }
    
    
    func customPhoto(img: CIImage, withAmount intensity: Float) -> CIImage {
        // 1
        let sepia = CIFilter(name:"CISepiaTone")
        sepia!.setValue(img, forKey:kCIInputImageKey)
        sepia!.setValue(intensity, forKey:"inputIntensity")
        
        // 2
        let random = CIFilter(name:"CIRandomGenerator")
        
        // 3
        let lighten = CIFilter(name:"CIColorControls")
        lighten!.setValue(random!.outputImage, forKey:kCIInputImageKey)
        lighten!.setValue(1 - intensity, forKey:"inputBrightness")
        lighten!.setValue(0, forKey:"inputSaturation")
        
        
   
        // 4
        let croppedImage = lighten!.outputImage!.imageByCroppingToRect(img.extent)
        
        // 5
        let composite = CIFilter(name:"CIHardLightBlendMode")
        composite!.setValue(sepia!.outputImage, forKey:kCIInputImageKey)
        composite!.setValue(croppedImage, forKey:kCIInputBackgroundImageKey)
        
        // 6
        let vignette = CIFilter(name:"CIVignette")
        vignette!.setValue(composite!.outputImage, forKey:kCIInputImageKey)
        vignette!.setValue(intensity * 2, forKey:"inputIntensity")
        vignette!.setValue(intensity * 30, forKey:"inputRadius")
        
        // 7
        return vignette!.outputImage!
    }
    
    
    func oldFilmPhoto(img: CIImage, withAmount intensity: Float) -> CIImage {
        // 1
        let sepia = CIFilter(name:"CISepiaTone")
        sepia!.setValue(img, forKey:kCIInputImageKey)
        sepia!.setValue(intensity, forKey:"inputIntensity")
        
        
        let random = CIFilter(name:"CIRandomGenerator")
//        random?.setValue(0.3, forKey: "inputIntensity")
        var croppedRandomImage : CIImage!
        if #available(iOS 8.0, *) {
            croppedRandomImage = random!.outputImage!.imageByClampingToExtent()
        } else {
            // Fallback on earlier versions
        }
//        let transformImage = random!.outputImage!.imageByApplyingTransform(CGAffineTransformMakeScale(1.0, 1.0))

         2
        let colorMatrix = CIFilter(name:"CIColorMatrix")
        
        colorMatrix!.setValue(croppedRandomImage, forKey:kCIInputImageKey)
        colorMatrix!.setValue(CIVector(values: [0, 1, 0, 0], count: 4), forKey:"inputRVector")
        colorMatrix!.setValue(CIVector(values: [0, 1, 0, 0], count: 4), forKey:"inputGVector")
        colorMatrix!.setValue(CIVector(values: [0, 1, 0, 0], count: 4), forKey:"inputBVector")
        colorMatrix!.setValue(CIVector(values: [0, 0, 0, 0], count: 4), forKey:"inputBiasVector")

        

        
        // 3 (sepia tone, white specks)
        let sourceOverCompositing = CIFilter(name:"CISourceOverCompositing")
        sourceOverCompositing!.setValue(colorMatrix?.outputImage, forKey:kCIInputImageKey)
        sourceOverCompositing!.setValue(sepia!.outputImage, forKey:"inputBackgroundImage")

        
        
        
        
//        // 4
        let random1 = CIFilter(name:"CIRandomGenerator")
//        let croppedRandom1Image = random1!.outputImage!.imageByCroppingToRect(img.extent)
        let transformImage1 = random1!.outputImage!.imageByApplyingTransform(CGAffineTransformMakeScale(1.5, 25.0))
        
        
        // 5
        let colorMatrix1 = CIFilter(name:"CIColorMatrix")
        
        colorMatrix1!.setValue(transformImage1, forKey:kCIInputImageKey)
        colorMatrix1!.setValue(CIVector(values: [4, 0, 0, 0], count: 4), forKey:"inputRVector")
        colorMatrix1!.setValue(CIVector(values: [0, 0, 0, 0], count: 4), forKey:"inputGVector")
        colorMatrix1!.setValue(CIVector(values: [0, 0, 0, 0], count: 4), forKey:"inputBVector")
        colorMatrix1!.setValue(CIVector(values: [0, 0, 0, 0], count: 4), forKey:"inputAVector")
        colorMatrix1!.setValue(CIVector(values: [0, 1, 1, 1], count: 4), forKey:"inputBiasVector")
        
        // 5.a
        let minimumComponent = CIFilter(name:"CIMinimumComponent")
        minimumComponent!.setValue(colorMatrix1?.outputImage, forKey:kCIInputImageKey)
        
        
        // 6
        let multiplyCompositing = CIFilter(name:"CIMultiplyCompositing")
        
        multiplyCompositing!.setValue(minimumComponent?.outputImage, forKey:kCIInputImageKey)
        multiplyCompositing!.setValue(sourceOverCompositing?.outputImage, forKey: "inputBackgroundImage")
        
        

        return multiplyCompositing!.outputImage!
    }
    
    
    
    var number = 0.0
    // MohsinDelegate
    func filterImageBuffer(sourceImage : CIImage) -> CIImage?{
        
        print("Mohsin delegate")
        
//        self.filter.setValue(CIVector(values: [200,200], count: 2), forKey: "inputCenter")
        self.filter.setValue(number, forKey: "inputAngle")
        number += 0.05
//        self.filter.setValue(sourceImage, forKey: kCIInputImageKey)
//        let filteredImage = self.filter.valueForKey(kCIOutputImageKey) as! CIImage?
        
        let filteredImage1 = self.oldFilmPhoto(sourceImage, withAmount: 0.9)


        
        
        
        
        return filteredImage1
    }

    
}