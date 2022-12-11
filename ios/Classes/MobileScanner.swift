//
//  SwiftMobileScanner.swift
//  mobile_scanner
//
//  Created by Julian Steenbakker on 15/02/2022.
//

import Foundation

import AVFoundation
import MLKitVision
import MLKitBarcodeScanning

typealias MobileScannerCallback = ((Array<Barcode>?, Error?, UIImage) -> ())

public class MobileScanner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, FlutterTexture {
    /// Capture session of the camera
    var captureSession: AVCaptureSession!

    /// The selected camera
    var device: AVCaptureDevice!

    /// Barcode scanner for results
    var scanner = BarcodeScanner.barcodeScanner()

    /// Return image buffer with the Barcode event
    var returnImage: Bool = false

    /// Default position of camera
    var videoPosition: AVCaptureDevice.Position = AVCaptureDevice.Position.back

    /// When results are found, this callback will be called
    let mobileScannerCallback: MobileScannerCallback

    /// If provided, the Flutter registry will be used to send the output of the CaptureOutput to a Flutter texture.
    private let registry: FlutterTextureRegistry?

    /// Image to be sent to the texture
    var latestBuffer: CVImageBuffer!

    /// Texture id of the camera preview for Flutter
    private var textureId: Int64!

    var detectionSpeed: DetectionSpeed = DetectionSpeed.noDuplicates
    
//    private lazy var sessionQueue = DispatchQueue

    init(registry: FlutterTextureRegistry?, mobileScannerCallback: @escaping MobileScannerCallback) {
        self.registry = registry
        self.mobileScannerCallback = mobileScannerCallback
        super.init()
    }

    /// Check if we already have camera permission.
    func checkPermission() -> Int {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            return 0
        case .authorized:
            return 1
        default:
            return 2
        }
    }

    /// Request permissions for video
    func requestPermission(_ result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: { result($0) })
    }
    
    /// Gets called when a new image is added to the buffer
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer.")
            return
        }
        
//        guard let ciImage = getImageFromSampleBuffer(buffer: sampleBuffer) else {
//            print("Failed to get image buffer from sample buffer.")
//            return
//        }

//        latestBuffer = imageBuffer
        registry?.textureFrameAvailable(textureId)
        
        if ((detectionSpeed == DetectionSpeed.normal || detectionSpeed == DetectionSpeed.noDuplicates) && i > 10 || detectionSpeed == DetectionSpeed.unrestricted) {
            i = 0
            if (latestBuffer?.image.ciImage == nil) {
                return
            }
            // Define the metadata for the image
            
//            let ciImage = getImageFromSampleBuffer(pixelBuffer: imageBuffer)

            let image = VisionImage(image: ciImagee)
//            let image = VisionImage(buffer: sampleBuffer)
//            image.orientation = .right
            image.orientation = imageOrientation(fromDevicePosition: videoPosition)
//            image.orientation = imageOrientation(
//                deviceOrientation: UIDevice.current.orientation,
//                defaultOrientation: .portrait,
//                position: videoPosition
//            )

            scanner.process(image) { [self] barcodes, error in
//                print(connection.)
                if (detectionSpeed == DetectionSpeed.noDuplicates) {
                    let newScannedBarcodes = barcodes?.map { barcode in
                        return barcode.rawValue
                    }
                    if (error == nil && barcodesString != nil && newScannedBarcodes != nil && barcodesString!.elementsEqual(newScannedBarcodes!)) {
                        return
                    } else {
                        barcodesString = newScannedBarcodes
                    }
                }

//                if scanWindow != nil {
//                    var yourArray = [Barcode]()
//                    for barcode in barcodes ?? [] {
//                        let match = isbarCodeInScanWindow(scanWindow!, barcode, ciImage)
//                        if (match) {
//                            yourArray.append(barcode)
//                        }
//                    }
//                    if (!yourArray.isEmpty) {
//                        mobileScannerCallback(yourArray, error, ciImage)
//                    }
//
//                } else {
                    mobileScannerCallback(barcodes, error, ciImagee)
//                }
                
                
            }
        } else {
            i+=1
        }
    }
    
//    func getImageFromSampleBuffer (pixelBuffer :CVImageBuffer) -> UIImage {
//        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
//
//        let srcWidth = CGFloat(ciImage.extent.width)
//        let srcHeight = CGFloat(ciImage.extent.height)
//
//        let dstWidth: CGFloat = 1080
//        let dstHeight: CGFloat = 1920
//
//        let scaleX = dstWidth / srcWidth
//        let scaleY = dstHeight / srcHeight
//        let scale = min(scaleX, scaleY)
//
//        let transform = CGAffineTransform.init(scaleX: scale, y: scale)
//        let output = ciImage.transformed(by: transform).cropped(to: CGRect(x: 0, y: 0, width: dstWidth, height: dstHeight))
//
//        return UIImage(ciImage: output)
//    }

    /// Start scanning for barcodes
    func start(barcodeScannerOptions: BarcodeScannerOptions?, returnImage: Bool, cameraPosition: AVCaptureDevice.Position, torch: AVCaptureDevice.TorchMode, detectionSpeed: DetectionSpeed) throws -> MobileScannerStartParameters {
        self.detectionSpeed = detectionSpeed
        if (device != nil) {
            throw MobileScannerError.alreadyStarted
        }

        scanner = barcodeScannerOptions != nil ? BarcodeScanner.barcodeScanner(options: barcodeScannerOptions!) : BarcodeScanner.barcodeScanner()
        captureSession = AVCaptureSession()
        textureId = registry?.register(self)

        // Open the camera device
        if #available(iOS 10.0, *) {
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition)
        } else {
            device = AVCaptureDevice.devices(for: .video).filter({$0.position == cameraPosition}).first
        }

        if (device == nil) {
            throw MobileScannerError.noCamera
        }

        // Enable the torch if parameter is set and torch is available
        if (device.hasTorch && device.isTorchAvailable) {
            do {
                try device.lockForConfiguration()
                device.torchMode = torch
                device.unlockForConfiguration()
            } catch {
                throw MobileScannerError.torchError(error)
            }
        }

        device.addObserver(self, forKeyPath: #keyPath(AVCaptureDevice.torchMode), options: .new, context: nil)
        captureSession.beginConfiguration()
//        let videoDevice = AVCaptureDevice.default(for: .video, position: cameraPosition)
//        captureSession.canAddInput(device)
        // Add device input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession.addInput(input)
        } catch {
            throw MobileScannerError.cameraError(error)
        }

        captureSession.sessionPreset = AVCaptureSession.Preset.high;
        // Add video output.
        let videoOutput = AVCaptureVideoDataOutput()

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
//        videoOutput.connection(with: .video)?.videoOrientation = .portrait

        videoPosition = cameraPosition
        // calls captureOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)

        captureSession.addOutput(videoOutput)
        for connection in videoOutput.connections {
            connection.videoOrientation = .portrait
////            if cameraPosition == .front && connection.isVideoMirroringSupported {
////                connection.isVideoMirrored = true
////            }
        }
        captureSession.commitConfiguration()
        captureSession.startRunning()
        
        
        let dimensions2 = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)

        let dimensions = CMVideoFormatDescriptionGetPresentationDimensions(device.activeFormat.formatDescription, usePixelAspectRatio: true, useCleanAperture: true)

        return MobileScannerStartParameters(width: Double(dimensions.width), height: Double(dimensions.height), hasTorch: device.hasTorch, textureId: textureId)
    }

    /// Stop scanning for barcodes
    func stop() throws {
        if (device == nil) {
            throw MobileScannerError.alreadyStopped
        }
        captureSession.stopRunning()
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.torchMode))
        registry?.unregisterTexture(textureId)
        textureId = nil
        captureSession = nil
        device = nil
    }

    /// Toggle the flashlight between on and off
    func toggleTorch(_ torch: AVCaptureDevice.TorchMode) throws {
        if (device == nil) {
            throw MobileScannerError.torchWhenStopped
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = torch
            device.unlockForConfiguration()
        } catch {
            throw MobileScannerError.torchError(error)
        }
    }

    /// Analyze a single image
    func analyzeImage(image: UIImage, position: AVCaptureDevice.Position, callback: @escaping BarcodeScanningCallback) {
        let image = VisionImage(image: image)
        
        image.orientation = imageOrientation(
//            deviceOrientation: UIDevice.current.orientation,
//            defaultOrientation: .portrait,
            fromDevicePosition: position
        )

        scanner.process(image, completion: callback)
    }
    
    
    var scanWindow: CGRect?
    
    func updateScanWindow(_ scanWindowData: [CGFloat]?) {
        if (scanWindowData == nil) {
            return
        }

        let minX = scanWindowData![0]
        let minY = scanWindowData![1]

        let width = scanWindowData![2]  - minX
        let height = scanWindowData![3] - minY

        scanWindow = CGRect(x: minX, y: minY, width: width, height: height)
    }
    
    func isbarCodeInScanWindow(_ scanWindow: CGRect, _ barcode: Barcode, _ inputImage: UIImage) -> Bool {
         let barcodeBoundingBox = barcode.frame

         let imageWidth = inputImage.size.width;
         let imageHeight = inputImage.size.height;

         let minX = scanWindow.minX * imageWidth
         let minY = scanWindow.minY * imageHeight
         let width = scanWindow.width * imageWidth
         let height = scanWindow.height * imageHeight

         let scaledScanWindow = CGRect(x: minX, y: minY, width: width, height: height)
         return scaledScanWindow.contains(barcodeBoundingBox)
    }

    var i = 0

    var barcodesString: Array<String?>?



//    /// Convert image buffer to jpeg
//    private func ciImageToJpeg(ciImage: CIImage) -> Data {
//
//        // let ciImage = CIImage(cvPixelBuffer: latestBuffer)
//        let context:CIContext = CIContext.init(options: nil)
//        let cgImage:CGImage = context.createCGImage(ciImage, from: ciImage.extent)!
//        let uiImage:UIImage = UIImage(cgImage: cgImage, scale: 1, orientation: UIImage.Orientation.up)
//
//        return uiImage.jpegData(compressionQuality: 0.8)!;
//    }

    /// Rotates images accordingly
//    func imageOrientation(
//        deviceOrientation: UIDeviceOrientation,
//        defaultOrientation: UIDeviceOrientation,
//        position: AVCaptureDevice.Position
//    ) -> UIImage.Orientation {
//        switch deviceOrientation {
//        case .portrait:
//            return position == .front ? .leftMirrored : .right
//        case .landscapeLeft:
//            return position == .front ? .downMirrored : .up
//        case .portraitUpsideDown:
//            return position == .front ? .rightMirrored : .left
//        case .landscapeRight:
//            return position == .front ? .upMirrored : .down
//        case .faceDown, .faceUp, .unknown:
//            return .up
//        @unknown default:
//            return imageOrientation(deviceOrientation: defaultOrientation, defaultOrientation: .portrait, position: .back)
//        }
//    }
    
    func imageOrientation(
      fromDevicePosition devicePosition: AVCaptureDevice.Position = .back
    ) -> UIImage.Orientation {
      var deviceOrientation = UIDevice.current.orientation
      if deviceOrientation == .faceDown || deviceOrientation == .faceUp
        || deviceOrientation
          == .unknown
      {
        deviceOrientation = currentUIOrientation()
      }
      switch deviceOrientation {
      case .portrait:
        return devicePosition == .front ? .leftMirrored : .right
      case .landscapeLeft:
        return devicePosition == .front ? .downMirrored : .up
      case .portraitUpsideDown:
        return devicePosition == .front ? .rightMirrored : .left
      case .landscapeRight:
        return devicePosition == .front ? .upMirrored : .down
      case .faceDown, .faceUp, .unknown:
        return .up
      @unknown default:
        fatalError()
      }
    }
    
    func currentUIOrientation() -> UIDeviceOrientation {
      let deviceOrientation = { () -> UIDeviceOrientation in
        switch UIApplication.shared.statusBarOrientation {
        case .landscapeLeft:
          return .landscapeRight
        case .landscapeRight:
          return .landscapeLeft
        case .portraitUpsideDown:
          return .portraitUpsideDown
        case .portrait, .unknown:
          return .portrait
        @unknown default:
          fatalError()
        }
      }
      guard Thread.isMainThread else {
        var currentOrientation: UIDeviceOrientation = .portrait
        DispatchQueue.main.sync {
          currentOrientation = deviceOrientation()
        }
        return currentOrientation
      }
      return deviceOrientation()
    }

    /// Sends output of OutputBuffer to a Flutter texture
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        if latestBuffer == nil {
            return nil
        }
        return Unmanaged<CVPixelBuffer>.passRetained(latestBuffer)
    }
    
    struct MobileScannerStartParameters {
        var width: Double = 0.0
        var height: Double = 0.0
        var hasTorch = false
        var textureId: Int64 = 0
    }
}

