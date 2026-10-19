import Flutter
import UIKit
import ObjectiveC
import UniformTypeIdentifiers
import MobileCoreServices

// MARK: - 状态栏隐藏（TrollStore 侧载版）
// 根控制器 FlutterViewController 由 Main.storyboard 实例化，无法替换类型；
// 因此通过关联对象 + 方法交换实现「阅读设置 → 操作 → 隐藏系统状态栏」开关。
// FlutterViewController 未重写 prefersStatusBarHidden，动态派发会命中
// UIViewController 的（已被交换的）实现，从而读取关联对象状态。

private var statusBarHiddenAssocKey: UInt8 = 0
private var statusBarSwizzleDone = false

extension UIViewController {
  @objc func w8_prefersStatusBarHidden() -> Bool {
    if self is FlutterViewController,
       let hidden = objc_getAssociatedObject(self, &statusBarHiddenAssocKey) as? Bool {
      return hidden
    }
    return w8_prefersStatusBarHidden()
  }
}

private func swizzleStatusBarAppearance() {
  guard !statusBarSwizzleDone else { return }
  statusBarSwizzleDone = true
  guard let original = class_getInstanceMethod(
          UIViewController.self,
          #selector(getter: UIViewController.prefersStatusBarHidden)),
        let swizzled = class_getInstanceMethod(
          UIViewController.self,
          #selector(UIViewController.w8_prefersStatusBarHidden)) else {
    return
  }
  method_exchangeImplementations(original, swizzled)
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pickerResult: FlutterResult?
  private var retainedPicker: UIViewController?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    swizzleStatusBarAppearance()
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "wenku8-ios-system") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/ios_system",
      binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "AppDelegate 已释放", details: nil))
        return
      }
      switch call.method {
      case "pickBooks":
        self.presentBookPicker(font: false, result: result)
      case "pickFont":
        self.presentBookPicker(font: true, result: result)
      case "setStatusBarHidden":
        let hidden = (call.arguments as? [String: Any])?["hidden"] as? Bool ?? false
        self.applyStatusBar(hidden: hidden)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - 状态栏

  private func applyStatusBar(hidden: Bool) {
    guard let controller = rootViewController else { return }
    objc_setAssociatedObject(
      controller,
      &statusBarHiddenAssocKey,
      hidden,
      .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    DispatchQueue.main.async {
      controller.setNeedsStatusBarAppearanceUpdate()
    }
  }

  // MARK: - 文件选择（UIDocumentPicker，asCopy 直接复制进沙盒）

  private func presentBookPicker(font: Bool, result: @escaping FlutterResult) {
    guard pickerResult == nil else {
      result(FlutterError(code: "busy", message: "已有选择器在运行", details: nil))
      return
    }
    guard let root = rootViewController else {
      result(FlutterError(code: "no-root", message: "未找到根视图控制器", details: nil))
      return
    }
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      var types: [UTType] = [.plainText, .pdf]
      if font {
        types = [.font]
      } else {
        if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
        if let mobi = UTType(filenameExtension: "mobi") { types.append(mobi) }
        if let zip = UTType(filenameExtension: "zip") { types.append(zip) }
      }
      picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    } else {
      let types = font
        ? [kUTTypeFont as String]
        : [
            kUTTypePlainText as String,
            kUTTypePDF as String,
            "org.idpf.epub-container",
            "com.amazon.mobi8-ebook",
            kUTTypeZipArchive as String,
          ]
      picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
    }
    picker.allowsMultipleSelection = !font
    picker.delegate = self
    pickerResult = result
    retainedPicker = picker
    root.present(picker, animated: true, completion: nil)
  }

  private var rootViewController: UIViewController? {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      let window: UIWindow?
      if #available(iOS 15.0, *) {
        window = windowScene.keyWindow
      } else {
        window = windowScene.windows.first { $0.isKeyWindow }
      }
      if let root = window?.rootViewController {
        return root
      }
    }
    return nil
  }
}

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    // asCopy 模式：url 已是沙盒内的副本，可直接读取，无需安全作用域。
    let items = urls.map { ["name": $0.lastPathComponent, "path": $0.path] }
    finishPicker(items)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishPicker([])
  }

  private func finishPicker(_ items: [[String: String]]) {
    retainedPicker = nil
    pickerResult?(items)
    pickerResult = nil
  }
}
