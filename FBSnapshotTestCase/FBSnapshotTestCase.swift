import FBSnapshotTestCase
import QuartzCore
import UIKit
import XCTest

/*
 There are three ways of setting reference image directories.

 1. Set the preprocessor macro FB_REFERENCE_IMAGE_DIR to a double quoted
    c-string with the path.
 2. Set an environment variable named FB_REFERENCE_IMAGE_DIR with the path. This
    takes precedence over the preprocessor macro to allow for run-time override.
 3. Keep everything unset, which will cause the reference images to be looked up
    inside the bundle holding the current test, in the
    Resources/ReferenceImages_* directories.
 */
#if !FB_REFERENCE_IMAGE_DIR
let FB_REFERENCE_IMAGE_DIR = ""
#endif
/**
 Similar to our much-loved XCTAssert() macros. Use this to perform your test. No need to write an explanation, though.
 @param view The view to snapshot
 @param identifier An optional identifier, used if there are multiple snapshot tests in a given -test method.
 @param suffixes An NSOrderedSet of strings for the different suffixes
 @param tolerance The percentage of pixels that can differ and still count as an 'identical' view
 */
func FBSnapshotVerifyViewWithOptions(view__: Any, identifier__: Any, suffixes__: Any, tolerance__: Any) {
    FBSnapshotVerifyViewOrLayerWithOptions(View, view__, identifier__, suffixes__, tolerance__)
}
func FBSnapshotVerifyView(view__: Any, identifier__: Any) {
    FBSnapshotVerifyViewWithOptions(view__, identifier__, FBSnapshotTestCaseDefaultSuffixes(), 0)
}
/**
 Similar to our much-loved XCTAssert() macros. Use this to perform your test. No need to write an explanation, though.
 @param layer The layer to snapshot
 @param identifier An optional identifier, used if there are multiple snapshot tests in a given -test method.
 @param suffixes An NSOrderedSet of strings for the different suffixes
 @param tolerance The percentage of pixels that can differ and still count as an 'identical' layer
 */
func FBSnapshotVerifyLayerWithOptions(layer__: Any, identifier__: Any, suffixes__: Any, tolerance__: Any) {
    FBSnapshotVerifyViewOrLayerWithOptions(Layer, layer__, identifier__, suffixes__, tolerance__)
}
func FBSnapshotVerifyLayer(layer__: Any, identifier__: Any) {
    FBSnapshotVerifyLayerWithOptions(layer__, identifier__, FBSnapshotTestCaseDefaultSuffixes(), 0)
}
func FBSnapshotVerifyViewOrLayerWithOptions(what__: Any, viewOrLayer__: Any, identifier__: Any, suffixes__: Any, tolerance__: Any) {
    var errorDescription = snapshotVerifyViewOrLayer(viewOrLayer__, identifier: identifier__, suffixes: suffixes__, tolerance: tolerance__, defaultReferenceDirectory: (FB_REFERENCE_IMAGE_DIR))
    var noErrors: Bool = errorDescription == nil
    XCTAssertTrue(noErrors, "%@", errorDescription)
}
/**
 The base class of view snapshotting tests. If you have small UI component, it's often easier to configure it in a test
 and compare an image of the view to a reference image that write lots of complex layout-code tests.
 
 In order to flip the tests in your subclass to record the reference images set @c recordMode to @c YES.
 
 @attention When recording, the reference image directory should be explicitly
            set, otherwise the images may be written to somewhere inside the
            simulator directory.

 For example:
 @code
 - (void)setUp
 {
    [super setUp];
    self.recordMode = YES;
 }
 @endcode
 */
class FBSnapshotTestCase: XCTestCase {
    /**
     When YES, the test macros will save reference images, rather than performing an actual test.
     */

    var recordMode: Bool {
        get {
            return snapshotController?._recordMode ?? false
        }
        set(recordMode) {
            assert(snapshotController != nil, "\(#function) cannot be called before [super setUp]")
            snapshotController?.recordMode = recordMode
        }
    }
    /**
     When @c YES appends the name of the device model and OS to the snapshot file name.
     The default value is @c NO.
     */
    var deviceAgnostic: Bool {
        get {
            return snapshotController?._deviceAgnostic ?? false
        }
        set(deviceAgnostic) {
            assert(snapshotController != nil, "\(#function) cannot be called before [super setUp]")
            snapshotController?.deviceAgnostic = deviceAgnostic
        }
    }
    /**
     When set, allows fine-grained control over how agnostic you want the file names to be.
    
     Allows you to combine which agnostic options you want in your snapshot file names.
    
     The default value is FBSnapshotTestCaseAgnosticOptionNone.
    
     @attention If deviceAgnostic is YES, this bitmask is ignored. deviceAgnostic will be deprecated in a future version of FBSnapshotTestCase.
     */
    var agnosticOptions: FBSnapshotTestCaseAgnosticOption {
        get {
            return (snapshotController?._agnosticOptions)!
        }
        set(agnosticOptions) {
            assert(snapshotController != nil, "\(#function) cannot be called before [super setUp]")
            snapshotController?.agnosticOptions = agnosticOptions
        }
    }
    /**
     When YES, renders a snapshot of the complete view hierarchy as visible onscreen.
     There are several things that do not work if renderInContext: is used.
     - UIVisualEffect #70
     - UIAppearance #91
     - Size Classes #92
     
     @attention If the view does't belong to a UIWindow, it will create one and add the view as a subview.
     */
    var usesDrawViewHierarchyInRect: Bool {
        get {
            return snapshotController?._usesDrawViewHierarchyInRect ?? false
        }
        set(usesDrawViewHierarchyInRect) {
            assert(snapshotController != nil, "\(#function) cannot be called before [super setUp]")
            snapshotController?.usesDrawViewHierarchyInRect = usesDrawViewHierarchyInRect
        }
    }

    private var snapshotController: FBSnapshotTestController?

// MARK: - Overrides

    override class func setUp() {
        super.setUp()
        snapshotController = FBSnapshotTestController(testName: NSStringFromClass(FBSnapshotTestCase.self))
    }

    override class func tearDown() {
        snapshotController = nil
        super.tearDown()
    }

    /**
     Performs the comparison or records a snapshot of the layer if recordMode is YES.
     @param viewOrLayer The UIView or CALayer to snapshot
     @param identifier An optional identifier, used if there are multiple snapshot tests in a given -test method.
     @param suffixes An NSOrderedSet of strings for the different suffixes
     @param tolerance The percentage difference to still count as identical - 0 mean pixel perfect, 1 means I don't care
     @param defaultReferenceDirectory The directory to default to for reference images.
     @returns nil if the comparison (or saving of the reference image) succeeded. Otherwise it contains an error description.
     */
    func snapshotVerifyViewOrLayer(_ viewOrLayer: Any?, identifier: String?, suffixes: NSOrderedSet?, tolerance: CGFloat, defaultReferenceDirectory: String?) -> String? {
        if nil == viewOrLayer {
            return "Object to be snapshotted must not be nil"
        }
        let referenceImageDirectory = getReferenceImageDirectory(withDefault: defaultReferenceDirectory)
        if referenceImageDirectory == nil {
            return "Missing value for referenceImagesDirectory - Set FB_REFERENCE_IMAGE_DIR as Environment variable in your scheme."
        }
        if suffixes?.count == 0 {
            if let aSuffixes = suffixes {
                return "Suffixes set cannot be empty \(aSuffixes)"
            }
            return nil
        }
        var testSuccess = false
        var error: Error? = nil
        var errors = [AnyHashable]()
        if recordMode {
            var referenceImagesDirectory: String? = nil
            if let anObject = suffixes?.first {
                referenceImagesDirectory = "\(referenceImageDirectory ?? "")\(anObject)"
            }
            let referenceImageSaved = try? _compareSnapshotOfViewOrLayer(viewOrLayer, referenceImagesDirectory: referenceImagesDirectory, identifier: tolerance as? identifier, tolerance)
            if !referenceImageSaved {
                if let anError = error {
                    errors.append(anError)
                }
            }
        } else {
            for suffix: String? in suffixes ?? [String?]() {
                let referenceImagesDirectory = "\(referenceImageDirectory ?? "")\(suffix ?? "")"
                let referenceImageAvailable = referenceImageRecorded(inDirectory: referenceImagesDirectory, identifier: error as? identifier, &error)
                if referenceImageAvailable {
                    let comparisonSuccess = try? self._compareSnapshotOfViewOrLayer(viewOrLayer, referenceImagesDirectory: referenceImagesDirectory, identifier: identifier, tolerance: tolerance)
                    errors.removeAll()
                    if comparisonSuccess ?? false {
                        testSuccess = true
                        break
                    } else {
                        if let anError = error {
                            errors.append(anError)
                        }
                    }
                } else {
                    if let anError = error {
                        errors.append(anError)
                    }
                }
            }
        }
        if !testSuccess {
            if let anObject = errors.first {
                return "Snapshot comparison failed: \(anObject)"
            }
            return nil
        }
        if recordMode {
            return "Test ran in record mode. Reference image is now saved. Disable record mode to perform an actual snapshot comparison!"
        }
        return nil
    }

    /**
     Performs the comparison or records a snapshot of the layer if recordMode is YES.
     @param layer The Layer to snapshot
     @param referenceImagesDirectory The directory in which reference images are stored.
     @param identifier An optional identifier, used if there are multiple snapshot tests in a given -test method.
     @param tolerance The percentage difference to still count as identical - 0 mean pixel perfect, 1 means I don't care
     @param errorPtr An error to log in an XCTAssert() macro if the method fails (missing reference image, images differ, etc).
     @returns YES if the comparison (or saving of the reference image) succeeded.
     */
    func compareSnapshotOf(_ layer: CALayer?, referenceImagesDirectory: String?, identifier: String?, tolerance: CGFloat) throws {
        return try? self._compareSnapshotOfViewOrLayer(layer, referenceImagesDirectory: referenceImagesDirectory, identifier: identifier, tolerance: tolerance) ?? false
    }

    /**
     Performs the comparison or records a snapshot of the view if recordMode is YES.
     @param view The view to snapshot
     @param referenceImagesDirectory The directory in which reference images are stored.
     @param identifier An optional identifier, used if there are multiple snapshot tests in a given -test method.
     @param tolerance The percentage difference to still count as identical - 0 mean pixel perfect, 1 means I don't care
     @param errorPtr An error to log in an XCTAssert() macro if the method fails (missing reference image, images differ, etc).
     @returns YES if the comparison (or saving of the reference image) succeeded.
     */
    func compareSnapshotOf(_ view: UIView?, referenceImagesDirectory: String?, identifier: String?, tolerance: CGFloat) throws {
        return try? self._compareSnapshotOfViewOrLayer(view, referenceImagesDirectory: referenceImagesDirectory, identifier: identifier, tolerance: tolerance) ?? false
    }

    /**
     Checks if reference image with identifier based name exists in the reference images directory.
     @param referenceImagesDirectory The directory in which reference images are stored.
     @param identifier An optional identifier, used if there are multiple snapshot tests in a given -test method.
     @param errorPtr An error to log in an XCTAssert() macro if the method fails (missing reference image, images differ, etc).
     @returns YES if reference image exists.
     */
    func referenceImageRecorded(inDirectory referenceImagesDirectory: String?, identifier: String?) throws {
        assert(snapshotController != nil, "\(#function) cannot be called before [super setUp]")
        snapshotController?.referenceImagesDirectory = referenceImagesDirectory ?? ""
        var referenceImage: UIImage? = nil
        if let aSelector = invocation?.selector {
            referenceImage = try? snapshotController?.referenceImage(for: aSelector, identifier: identifier)
        }
        return referenceImage != nil
    }

    /**
     Returns the reference image directory.
    
     Helper function used to implement the assert macros.
    
     @param dir directory to use if environment variable not specified. Ignored if null or empty.
     */
    func getReferenceImageDirectory(withDefault dir: String?) -> String? {
        let envReferenceImageDirectory = ProcessInfo.processInfo.environment["FB_REFERENCE_IMAGE_DIR"] as? String
        if envReferenceImageDirectory != nil {
            return envReferenceImageDirectory
        }
        if dir != nil && (dir?.count ?? 0) > 0 {
            return dir
        }
        return URL(fileURLWithPath: Bundle(for: FBSnapshotTestCase).resourcePath ?? "").appendingPathComponent("ReferenceImages").absoluteString
    }

// MARK: - Public API

// MARK: - Private API
    func _compareSnapshotOfViewOrLayer(_ viewOrLayer: Any?, referenceImagesDirectory: String?, identifier: String?, tolerance: CGFloat) throws {
        snapshotController?.referenceImagesDirectory = referenceImagesDirectory ?? ""
        if let aSelector = invocation?.selector {
            return try? snapshotController?.compareSnapshotOfViewOrLayer(viewOrLayer, selector: aSelector, identifier: identifier, tolerance: tolerance) ?? false
        }
        return false
    }
}
