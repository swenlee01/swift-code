//
//  ScannerViewController.swift
//  SPassUI
//
//  Created by Swen Lee on 14/02/2025.
//

import Foundation
import SwiftUI
import UIKit
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import WalletSPFWCollab
import MiSignetHelper

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, UISheetPresentationControllerDelegate {
    
    // MARK: - Properties
    private var session: AVCaptureSession = .init()
    private var qrOutput: AVCaptureMetadataOutput = .init()
    private var qrDelegate: QRScannerDelegate = .init()
    
    private var errorMessage: String = ""
    private var showError: Bool = false
    private var scannedResult: String = ""
    private var showScannedResult: Bool = false
    private var cameraPermission: Permission = .idle
    private var scannedCode: String = ""
    
    //Display Scanner UI or Qr Code
    private var showScannerUIxQrCode: Bool = true
    
    private var showAlert: Bool = false
    private var alertMessage: String = ""
    private var showLoggedInAlert: Bool = false
    private var inCorrectQrAction: Bool = false
    private var tokenExists: Bool = false
    
    private let width: CGFloat = UIScreen.main.bounds.width
    var fromVC: ScannerFrom
    
    private var prevTag: Int?
    private var cameraVC: CameraViewController?
    private var walletQRVC: WalletQRViewController?
    private var currentChildVC: UIViewController?
    
    required init(fromVC: ScannerFrom) {
        self.fromVC = fromVC
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    private lazy var topBarView: UIView = {
        let view = UIView()
        view.backgroundColor = SPassTheme.pageBackgroundColor()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(navStackView)
        view.addSubview(switchQRTabView)
        
        NSLayoutConstraint.activate([
            navStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.topAnchor),
            navStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.leadingAnchor),
            navStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: Constants.trailingAnchor),
            
            switchQrStackView.topAnchor.constraint(equalTo: navStackView.bottomAnchor, constant: 18),
            
            switchQRTabView.topAnchor.constraint(equalTo: switchQrStackView.topAnchor, constant: -6),
            switchQRTabView.bottomAnchor.constraint(equalTo: switchQrStackView.bottomAnchor, constant: 6),
            switchQRTabView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            switchQRTabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
        ])
        
        return view
    }()
    
    private lazy var navStackView: UIStackView = SharedDesign.createSubPageTitleStackView(titleLabel: titleLabel, closeButton: closeButton)
    
    private lazy var scanQRTab: UIStackView = self.configTabs(for: NSLocalizedString("LABEL_SCAN_QR", comment: "Label - Scan QR"), index: 0)
    private lazy var myQRTab: UIStackView = self.configTabs(for: NSLocalizedString("LABEL_MY_QR_CODE", comment: "Label - My QR Code"), index: 1)
    
    private lazy var switchQrStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [scanQRTab, myQRTab])
        stackView.distribution = .fillEqually
        stackView.spacing = 6
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            scanQRTab.heightAnchor.constraint(equalToConstant: 34),
            myQRTab.heightAnchor.constraint(equalToConstant: 34)
        ])
        
        if fromVC == .login || fromVC == .mainSelection {
            myQRTab.isHidden = true
            scanQRTab.isUserInteractionEnabled = false
        }
        
        return stackView
    }()
    
    private lazy var switchQRTabView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 10
        view.backgroundColor = SPassTheme.qrScannerTabBgColor() // SPassColors.scannerQRTabBgColor()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(switchQrStackView)
        
        NSLayoutConstraint.activate([
            switchQrStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            switchQrStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
        ])
        
        return view
    }()
    
    private lazy var titleLabel: UILabel = SharedDesign.createSubPageTitleLabel(NSLocalizedString("LABEL_QR_SCANNER", comment: "Label - QR Scanner"))
    
    private lazy var closeButton: UIButton = {
        let button = SharedDesign.createCloseButton()
        button.addTarget(self, action: #selector(dismissView), for: .touchUpInside)
        return button
    }()
    
    private lazy var scanFrame: UIImageView = {
        let baseImage = UIImage(named: SPassImages.scan_frame)?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: baseImage)
        //        let imageView = UIImageView(image: UIImage(named: SPassImages.scan_frame))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private func updateScanFrame(for traitCollection: UITraitCollection) {
        guard let baseImage = UIImage(named: SPassImages.scan_frame) else { return }
        
        if traitCollection.userInterfaceStyle == .dark {
            scanFrame.image = baseImage.withRenderingMode(.alwaysTemplate)
            scanFrame.tintColor = SPassColors.topNavBgColor
        } else {
            scanFrame.image = baseImage.withRenderingMode(.alwaysOriginal)
            scanFrame.tintColor = nil
        }
    }
    
    /*override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
     super.traitCollectionDidChange(previousTraitCollection)
     updateScanFrame(for: traitCollection)
     }*/
    
    /*private lazy var scanFrame: UIImageView = {
     let imageView = UIImageView(image: UIImage(named: "scanFrame"))
     imageView.contentMode = .scaleAspectFit
     imageView.translatesAutoresizingMaskIntoConstraints = false
     return imageView
     }()*/
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme(_:)), name: .themeDidChange, object: nil)
        
        applyTheme(nil)
        
        setupStaticUI()
        //        setupCameraUI()
        checkCameraPermission()
        selectTabWithTag(800)
        
        //  updateScanFrame(for: self.traitCollection)
    }
    
    @objc func applyTheme(_ notification: Notification?) {
        scanFrame.tintColor = SPassTheme.scannerColor()
    }
    
    private let childContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private func setupStaticUI() {
        view.addSubview(topBarView)
        view.addSubview(childContainerView)
        
        NSLayoutConstraint.activate([
            topBarView.topAnchor.constraint(equalTo: self.view.topAnchor),
            topBarView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            topBarView.bottomAnchor.constraint(equalTo: switchQrStackView.bottomAnchor, constant: 22),
            
            childContainerView.topAnchor.constraint(equalTo: topBarView.bottomAnchor),
            childContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            childContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            childContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func switchToChildViewController(_ newVC: UIViewController) {
        if let current = currentChildVC {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        
        addChild(newVC)
        newVC.view.frame = childContainerView.bounds
        newVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        childContainerView.addSubview(newVC.view)
        newVC.didMove(toParent: self)
        currentChildVC = newVC
    }
    
    private func setupCameraUI() {
        view.backgroundColor = .black
        let cameraVC = CameraViewController()
        cameraVC.session = session
        cameraVC.frameSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        addChild(cameraVC)
        view.addSubview(cameraVC.view)
        cameraVC.didMove(toParent: self)
        
        view.addSubview(topBarView)
        view.addSubview(scanFrame)
        
        NSLayoutConstraint.activate([
            topBarView.topAnchor.constraint(equalTo: self.view.topAnchor),
            topBarView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            topBarView.bottomAnchor.constraint(equalTo: switchQrStackView.bottomAnchor, constant: 22),
            
            scanFrame.widthAnchor.constraint(equalToConstant: 260),
            scanFrame.heightAnchor.constraint(equalToConstant: 260),
            scanFrame.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            scanFrame.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: 30),
        ])
    }
    
    private func removeCameraUI() {
        // Remove child camera VC if it was added
        if let cameraVC = self.children.first(where: { $0 is CameraViewController }) {
            cameraVC.willMove(toParent: nil)
            cameraVC.view.removeFromSuperview()
            cameraVC.removeFromParent()
        }
        
        // Remove overlays
        scanFrame.removeFromSuperview()
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermission = .approved
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.cameraPermission = .approved
                        self.setupCamera()
                    } else {
                        self.cameraPermission = .denied
//                        self.presentError(NSLocalizedString("ERROR_CAMERA_ACCESS_DENIED", comment: "Error - Camera access denied"))
                        CustomAlert.show(message: NSLocalizedString("ERROR_CAMERA_ACCESS_DENIED", comment: "Error - Camera access denied"))
                    }
                }
            }
        case .denied, .restricted:
            cameraPermission = .denied
//            self.presentError(NSLocalizedString("ERROR_CAMERA_ACCESS_DENIED", comment: "Error - Camera access denied"))
            CustomAlert.show(message: NSLocalizedString("ERROR_CAMERA_ACCESS_DENIED", comment: "Error - Camera access denied"))
        default:
            break
        }
    }
    
    private func configTabs(for labelText: String, index: Int) -> UIStackView {
        let label = UILabel()
        label.text = labelText
        label.font = OutfitFont.medium.font(size: 16)
        label.textColor = index == 0 ? UIColor.white : SPassTheme.primaryTextColor()
        label.tag = 700 + index
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        
        let stackview = UIStackView(arrangedSubviews: [label])
        stackview.axis = .vertical
        stackview.alignment = .center
        stackview.layer.cornerRadius = 6
        stackview.backgroundColor = index == 0 ? SPassTheme.getThemeColor() : .clear
        stackview.tag = 800 + index
        stackview.translatesAutoresizingMaskIntoConstraints = false
        stackview.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectTab(_:))))
        
        return stackview
    }
    
    private func setupCamera() {
        do {
            guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first else {
//                presentError("")
                CustomAlert.show(message: "")
                return
            }
            
            let input = try AVCaptureDeviceInput(device: device)
            
            guard session.canAddInput(input), session.canAddOutput(qrOutput) else {
//                presentError("")
                CustomAlert.show(message: "")
                return
            }
            
            session.beginConfiguration()
            session.addInput(input)
            session.addOutput(qrOutput)
            
            qrOutput.metadataObjectTypes = [.qr]
            qrOutput.setMetadataObjectsDelegate(self, queue: .main)
            session.commitConfiguration()
            
            //May 15 2025 Fixed the potential race condition which causes the app crash for the scanner
            //            DispatchQueue.global(qos: .background).async {
            //                self.session.startRunning()
            //            }
            
        } catch {
//            presentError(error.localizedDescription)
            CustomAlert.show(message: error.localizedDescription)
        }
    }
    
    @objc private func selectTab(_ sender: UITapGestureRecognizer) {
        guard let tappedTag = sender.view?.tag else { return }
        
        // If user tapped the same tab, ignore
        if tappedTag == prevTag {
            return
        }
        
        UIView.animate(withDuration: 0.3) {
            self.selectTabWithTag(tappedTag)
            self.prevTag = tappedTag
        }
        
        /*UIView.animate(withDuration: 0.3) {
         if sender.view?.tag == 800 {
         self.selectTabWithTag(800)
         self.prevTag = sender.view?.tag
         } else if sender.view?.tag == 801 {
         self.selectTabWithTag(801)
         self.prevTag = sender.view?.tag
         }
         }*/
    }
    
    //    @objc private func selectTab(_ sender: UITapGestureRecognizer) {
    //        guard let scanQRLabel = self.view.viewWithTag(700) as? UILabel, let myQRLabel = self.view.viewWithTag(701) as? UILabel else {
    //            return
    //        }
    //
    //        UIView.animate(withDuration: 0.3) {
    //            if sender.view?.tag == 800 {
    //                self.scanQRTab.backgroundColor = UIColor(hex: "#00668C")
    //                self.myQRTab.backgroundColor = .clear
    //                scanQRLabel.textColor = UIColor.white
    //                myQRLabel.textColor = SPassTheme.primaryTextColor()
    //            } else if sender.view?.tag == 801 {
    //                self.scanQRTab.backgroundColor = .clear
    //                self.myQRTab.backgroundColor = UIColor(hex: "#00668C")
    //                scanQRLabel.textColor = SPassTheme.primaryTextColor()
    //                myQRLabel.textColor = UIColor.white
    //            }
    //        }
    //    }
    
    private func selectTabWithTag(_ tag: Int) {
        guard let scanQRLabel = self.view.viewWithTag(700) as? UILabel,
              let myQRLabel = self.view.viewWithTag(701) as? UILabel else { return }
        
        if tag == prevTag { return }
        prevTag = tag
        
        UIView.animate(withDuration: 0.3) {
            
            // if tag == 800 && self.prevTag != 800 { //Prevents user from spamming the tab
            if tag == 800 {
                self.scanQRTab.backgroundColor = SPassTheme.qrScannerTabSelectedBgColor()
                self.myQRTab.backgroundColor = .clear
                scanQRLabel.textColor = SPassColors.lightText
                myQRLabel.textColor = SPassTheme.primaryTextColor()
                
                //Upon displaying the camera we will stop the Wallet BLE session
                self.walletQRVC?.stopWalletQR()
                
                //MARK: CRASH FIXED Apr 17 2025
                //Experienced app crash here due to camera unable to initiate APR 16 2025
                //Need more testing
                
                //we reset walletQRVC view controller to prevent crashes
                self.walletQRVC = nil
                
                self.setupCameraUI()
                
                if self.cameraVC == nil {
                    self.cameraVC = CameraViewController()
                    self.cameraVC?.session = self.session
                    self.cameraVC?.frameSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                }
                
                if let cameraVC = self.cameraVC {
                    //Calling the session start on the background thread to prevent UI unresponsive bug
                    //                        DispatchQueue.gl8obal(qos: .background).async {
                    DispatchQueue.main.async {
                        self.cameraVC?.session.startRunning()
                    }
                    
                    self.switchToChildViewController(cameraVC)
                    self.childContainerView.backgroundColor = .black
                }
            } else if tag == 801 {
                //            } else if tag == 801 && self.prevTag != 801 { //Prevents user from spamming the tab
                self.scanQRTab.backgroundColor = .clear
                self.myQRTab.backgroundColor = SPassTheme.qrScannerTabSelectedBgColor()
                scanQRLabel.textColor = SPassTheme.primaryTextColor()
                myQRLabel.textColor = SPassColors.lightText
                
                if self.cameraVC?.session.isRunning == true {
                    self.cameraVC?.session.stopRunning()
                }
            
                self.removeCameraUI()
                
                self.walletQRVC?.generateWalletQR(fallbackBLE: false)
                //                self.walletQRVC?.walletStatus()
                
                //we reset cameraVC view controller to prevent crashes
                self.cameraVC = nil
                
                if self.walletQRVC == nil {
                    self.walletQRVC = WalletQRViewController()
                    self.walletQRVC?.frameSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                }
                
                if let walletQRVC = self.walletQRVC {
                    self.switchToChildViewController(walletQRVC)
                    self.childContainerView.backgroundColor = SPassColors.lightText
                }
            }
        }
    }
    
    private func presentError(_ message: String) {
        let alert = UIAlertController(title: NSLocalizedString("LABEL_ERROR", comment: "Label - Error"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: "Button text - OK"), style: .default))
        present(alert, animated: true)
    }
    
    private func presentError(_ message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(
            title: NSLocalizedString("LABEL_ERROR", comment: "Label - Error"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("BUTTON_OK", comment: "Button text - OK"),
            style: .default,
            handler: { _ in
                completion?()
            }
        ))
        present(alert, animated: true)
    }
    
    @objc private func dismissView() {
        // Stop camera session immediately
        if self.session.isRunning {
            self.session.stopRunning()
        }
        
        self.walletQRVC?.stopWalletQR()
        self.dismiss(animated: true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Restart camera session if we are on the scanner tab
        if prevTag == 800 {
            if !self.session.isRunning {
                DispatchQueue.global(qos: .background).async {
                    self.session.startRunning()
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        // Stop camera session synchronously when view is   disappearing
        if self.session.isRunning {
            self.session.stopRunning()
        }
        super.viewWillDisappear(animated)
    }
}

extension ScannerViewController {
    // MARK: - QR Code Handling
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let jsonStructure = metadataObject.stringValue {
            handleScannedCode(jsonStructure)
        }
    }
    
    private func handleScannedCode(_ jsonStruct: String) {
        Logs.Print("Scanned QR is: \(jsonStruct)")
        // reset
        SPassDetails.shared.isFromQR = false
        
        // Stop immediately on main thread
        self.session.stopRunning()
        //If it's the json string qr code it will proceed with the consent sheet, else if it will return nil and use the usual url string
        
        if let jsonModel = ApiRequest.URLRequestJson(jsonString: jsonStruct) {
            Logs.Print("Decoded JSON is \(jsonModel)")
            //DIW Sep 08 Handle Json Qr code
            //If user is logged in status
            if jsonModel.client_id == SupportedClientID.spass_iam.rawValue && WSPFWCollab.login.DiwCheckUserLoginStatus() {
                if jsonModel.action == "AUTH_STATE" {
                    Logs.Print("This is our SwkID qr code, proceed")
                    NotificationCenter.default.postNotificationNameAsync(.showLoadingOverlay, object: nil)
                    Task {
                        let uiResults = try await WSPFWCollab.qrLoginhandler.callQRLogin(mobile_url: jsonModel.param?.diwParam?.mobile_url ?? "")
                        //                    print(uiResults)
                        
                        if uiResults.success {
                            //DIW Sep 08
                            //Qr login done
                            DispatchQueue.main.async {
                                self.dismissView()
                                NotificationCenter.default.post(name: NSNotification.Name("qrLoginPopUpConsentSheet"), object: uiResults.data)
                                
                            }
                        } else {
                            Logs.Print("failed to login")
                            if uiResults.code == "-1" {
                                //DIW Dec 09 Qr code login failed -> generic fail message
                                CustomAlert.show(message: NSLocalizedString("ERROR_INTERNET_OFFLINE", comment: "Error - Internet offline"), primaryAction: {
                                    self.dismissView()
                                    NotificationCenter.default.post(name: NSNotification.Name("qrLoginPopUpConsentSheet"), object: uiResults.data)
                                })
                            } else {
                                Logs.Print("failed to login")
                                if uiResults.code == "-1" {
                                    //DIW Dec 09 Qr code login failed -> generic fail message
                                    CustomAlert.show(message: NSLocalizedString("ERROR_INTERNET_OFFLINE", comment: "Error - Internet offline"), primaryAction: {
                                        self.dismissView()
                                    })
                                } else {
                                    CustomAlert.show(message: uiResults.msg, code: uiResults.code, primaryAction: {
                                        self.dismissView()
                                    })
                                }
                            }
                            
                            DispatchQueue.main.async {
                                NotificationCenter.default.postNotificationNameAsync(.hideLoadingOverlay, object: nil)
                            }
                        }
                    }
                } else if jsonModel.action == "SPASS_IN_APP_AUTH_WEBVIEW" {
                    Logs.Print("This is SPASS_IN_APP_AUTH_WEBVIEW qr code, proceed")
                    
                    let webviewUrl = jsonModel.param?.sarawakkuSayangParam?.webview_url ?? ""
                    let clientID = jsonModel.param?.sarawakkuSayangParam?.client_id ?? ""
                    let clientName = jsonModel.param?.sarawakkuSayangParam?.client_name ?? ""
                    
                    Logs.Print("Extracted for webview: clientID=\(clientID), webview_url=\(webviewUrl), client_name=\(clientName)")
                    
                    SPassDetails.shared.isSPassInAppAuthWebview = true
                    SPassDetails.shared.inAppAuthWebviewUrl = webviewUrl
                    
                    DispatchQueue.main.async {
                        self.dismissView()
                        AppToAppHelper.shared.performAppToAppLogin(clientID: clientID, from: self)
                    }
                } else {
                    // Invalid QR
                    CustomAlert.show(message: NSLocalizedString("ERROR_INVALID_QR", comment: "Error - Invalid QR Code"), primaryAction: {
                        self.dismissView()
                    })
                }
            } else if jsonModel.client_id == SupportedClientID.mysignet.rawValue {
                Logs.Print("Detected as MyDigital ID QR Code")
                self.handleMyDIDScannedCode(jsonStruct)
                
//                CustomAlert.show(message: "\(jsonModel)", primaryAction: {
//                    self.dismissView()
//                })
            } else {
                if !WSPFWCollab.login.DiwCheckUserLoginStatus() {
                    CustomAlert.show(message: NSLocalizedString("ERROR_USER_NOT_LOGGED_IN", comment: "Error - User not logged in"), primaryAction: {
                        self.dismissView()
                    })
                } else {
                    // throw error here
                    // Invalid QR
                    CustomAlert.show(message: NSLocalizedString("ERROR_INVALID_QR", comment: "Error - Invalid QR Code"), primaryAction: {
                        self.dismissView()
                    })
                }
            }
        } else {
            if ShowFeature.tempMyDIDTest {
                guard let data = jsonStruct.data(using: .utf8) else {
                    fatalError("Unable to convert string to Data")
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let url = json["url"] as? String, url.contains("wss://dev-auth.digital-id.my") {
                            Logs.Print("Detected as MyDigital ID QR Code")
                            self.handleMyDIDScannedCode(jsonStruct)
                        } else {
                            CustomAlert.show(message: NSLocalizedString("ERROR_INVALID_QR", comment: "Error - Invalid QR Code"), primaryAction: {
                                self.dismissView()
                            })
                        }
                    } else {
                        CustomAlert.show(message: NSLocalizedString("ERROR_INVALID_QR", comment: "Error - Invalid QR Code"), primaryAction: {
                            self.dismissView()
                        })
                    }
                } catch {
                    CustomAlert.show(message: NSLocalizedString("ERROR_INVALID_QR", comment: "Error - Invalid QR Code"), primaryAction: {
                        self.dismissView()
                    })
                }
            } else {
                guard let url = URL(string: jsonStruct), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    Logs.Print("Invalid URL")
                    
                    //DIW Sep 08
                    alertMessage = NSLocalizedString("ERROR_INVALID_QR", comment: "Error - Invalid QR Code")
                    showAlert = true
                    DispatchQueue.main.async {
                        /*self.presentError(self.alertMessage) {
                         //Alert Dialog Box completion handler
                         self.dismissView()
                         }*/
                        CustomAlert.show(message: self.alertMessage, primaryAction: {
                            self.dismissView()
                        })
                    }
                    return
                }
                
                if jsonStruct.contains(SPassCreds.apiFetchSessionID()) {
                    Logs.Print("Login QR code with sessionid detected")
                    
                    let result = AuthUtility.checkAndRetrieveAuthToken()
                    tokenExists = result.exists
                    
                    if !tokenExists {
                        print("*********************No authToken found, means not logged in.")
                        showLoggedInAlert = true
                    } else {
                        print("*********************authToken found, means is logged in.")
                        let sessionID = components.queryItems?.first(where: { $0.name == "sessionID" })?.value ?? ""
                        Logs.Print("Captured sessionID from qr code is: \(sessionID)")
                        SPassDetails.shared.capturedSessionID = sessionID
                        qrCodeVerified(.confirmqr)
                    }
                } else if jsonStruct.contains(SPassCreds.apiFetchJourneyID()) {
                    Logs.Print("Registration QR code with journeyID detected")
                    
                    if LoginFunc.retrieveUserLoggedInStatus() == "1" {
                        loggedInErrorDimissView()
                        return
                    }
                    
                    if SPassDetails.shared.checkUsrLoggedInForQrCode {
                        inCorrectQrAction = true
                        print("qr registration inCorrectQrAction is true ")
                    } else {
                        let journeyID = components.queryItems?.first(where: { $0.name == "journeyid" })?.value ?? ""
                        let usrID = components.queryItems?.first(where: { $0.name == "usr_id" })?.value ?? ""
                        let documentType = components.queryItems?.first(where: { $0.name == "document_type" })?.value ?? ""
                        
                        Logs.DebugPrint("usr_id is \(usrID)")
                        Logs.DebugPrint("JourneyID get from web is: \(journeyID)")
                        Logs.DebugPrint("document type is \(documentType)")
                        
                        SPassDetails.shared.mobileLoginCode = 1001
                        SPassDetails.shared.capturedJourneyID = journeyID
                        SPassDetails.shared.capturedUserID = usrID
                        SPassDetails.shared.capturedDocumentType = IDType.allCases.first { $0.docType == documentType } ?? nil
                        SPassDetails.shared.selectedIDType = SPassDetails.shared.capturedDocumentType
                        
                        SPassDetails.shared.isFromQR = true
                        qrCodeVerified(.ekyc2)
                        Logs.Print("isFromQr is true here, qrcodeverfied will do ekyc2")
                    }
                } else if jsonStruct.contains(SPassCreds.apiForgotPassword()) {
                    Logs.Print("Forgot password QR code with ic number detected")
                    
                    if SPassDetails.shared.checkUsrLoggedInForQrCode {
                        inCorrectQrAction = true
                        print("qr forgot password inCorrectQrAction is true ")
                    } else {
                        let ic_number = components.queryItems?.first(where: { $0.name == "ic_no" })?.value ?? ""
                        SPassDetails.shared.isForgotPasswordQrScan = true
                        SPassDetails.shared.forgotPasswordIC = ic_number
                        qrCodeVerified(.forgotpw)
                    }
                    Logs.Print("qr forgot password ic number is: \(SPassDetails.shared.forgotPasswordIC)")
                } else if jsonStruct.contains(SPassCreds.apiFetchFaceToken()) {
                    Logs.Print("Registration QR code with face token detected")
                    
                    if SPassDetails.shared.checkUsrLoggedInForQrCode {
                        inCorrectQrAction = true
                        print("qr registration inCorrectQrAction is true ")
                    } else {
                        let encoded_token = components.queryItems?.first(where: { $0.name == "token" })?.value ?? ""
                        let usr_id = components.queryItems?.first(where: { $0.name == "usr_id" })?.value ?? ""
                        
                        Logs.DebugPrint("usr_id is \(usr_id)")
                        Logs.DebugPrint("Face token get from web is: \(encoded_token)")
                        
                        if let data = Data(base64Encoded: encoded_token), let decodedString = String(data: data, encoding: .utf8) {
                            Logs.DebugPrint("Decoded Base64 face token is: \(decodedString)")
                            SPassDetails.shared.faceVerifyToken = decodedString
                        } else {
                            Logs.Print("Failed to decode Base64 token.")
                        }
                        
                        SPassDetails.shared.capturedUserID = usr_id
                        SPassDetails.shared.mobileLoginCode = 1003
                        qrCodeVerified(.fv)
                    }
                } else if jsonStruct.contains("digitalwallet://") && WSPFWCollab.login.DiwCheckUserLoginStatus() {
                    //IAM login qr
                    //Jun DIW
                    //To use this scanner for QR Login using IAM
                    //First we have to make sure user is logged in
                    //using the sdk check user login status
                    NotificationCenter.default.postNotificationNameAsync(.showLoadingOverlay, object: nil)
                    Task {
                        let uiResults = try await WSPFWCollab.qrLoginhandler.callQRLogin(qrCode: jsonStruct)
                        Logs.Print(uiResults)
                        
                        if uiResults.success {
                            DispatchQueue.main.async {
                                SPassDetails.shared.capturedQRCodeLoginForIam = uiResults.data
                                self.qrCodeVerified(.qrLoginConsentSheet)
                            }
                            
                        } else {
                            Logs.Print("failed to login")
                            /*presentError("QR Code Login Failed") {
                             //Alert Dialog Box completion handler
                             self.dismissView()
                             }*/
                            //                        CustomAlert.show(message: "QR Code Login Failed", primaryAction: {
                            //                            self.dismissView()
                            //                        })
                            if uiResults.code == "-1" {
                                //DIW Dec 09 Qr code login failed -> generic fail message
                                CustomAlert.show(message: NSLocalizedString("ERROR_QR_LOGIN_FAILED", comment: "Error - QR Code Login Failed"), primaryAction: {
                                    self.dismissView()
                                })
                            } else {
                                CustomAlert.show(message: uiResults.msg, code: uiResults.code, primaryAction: {
                                    self.dismissView()
                                })
                            }
                        }
                        DispatchQueue.main.async {
                            NotificationCenter.default.postNotificationNameAsync(.hideLoadingOverlay, object: nil)
                        }
                    }
                } else if jsonStruct.contains(SPassCreds.deepLinkRegister()) {
                    Logs.Print("Registration QR code detected \(jsonStruct)")
                    
                    let documentType = components.queryItems?.first(where: { $0.name.lowercased() == "document_type" })?.value ?? ""
                    
                    if LoginFunc.retrieveUserLoggedInStatus() != "1" {
                        if documentType == IDType.passport.docType {
                            SPassDetails.shared.selectedIDType = .passport
                            Logs.Print("Presenting RegistrationViewController_SelectID, selecting passport")
                            let registrationVC = RegistrationViewController_SelectID()
                            let navController = UINavigationController(rootViewController: registrationVC)
                            navController.modalPresentationStyle = .fullScreen
                            present(navController, animated: true) {
                                DispatchQueue.main.async {
                                    registrationVC.handleCardSelection(tag: 1001)
                                }
                            }
                        } else if documentType == IDType.myKad.docType {
                            SPassDetails.shared.selectedIDType = .myKad
                            Logs.Print("Presenting RegistrationViewController_SelectID selecting mykad")
                            let registrationVC = RegistrationViewController_SelectID()
                            let navController = UINavigationController(rootViewController: registrationVC)
                            navController.modalPresentationStyle = .fullScreen
                            present(navController, animated: true) {
                                DispatchQueue.main.async {
                                    registrationVC.handleCardSelection(tag: 1000)
                                }
                            }
                        } else {
                            invalidQRCodeErrorDimissView()
                        }
                    } else {
                        loggedInErrorDimissView()
                    }
                } else if jsonStruct.contains(SPassCreds.deepLinkForgotPass2()) {
                    Logs.Print("Recover Password QR code detected \(jsonStruct)")
                    
                    let action = components.queryItems?.first(where: { $0.name.lowercased() == "action" })?.value?.lowercased() ?? ""
                    if LoginFunc.retrieveUserLoggedInStatus() != "1" {
                        if action == "forgotpassword" {
                            Logs.Print("Presenting RecoverAccountViewController")
                            let recoverVC = RecoverAccountViewController()
                            let navController = UINavigationController(rootViewController: recoverVC)
                            navController.modalPresentationStyle = .fullScreen
                            present(navController, animated: true) {
                                DispatchQueue.main.async {
                                    recoverVC.handleCardSelection(tag: 2001)
                                }
                            }
                        }
                    } else {
                        loggedInErrorDimissView()
                    }
                } else {
                    invalidQRCodeErrorDimissView()
                }
            }
        }
    }
    
    private func loggedInErrorDimissView() {
        Logs.Print("User Logged In, and should not be able to register")
        alertMessage = NSLocalizedString("ERROR_USER_LOGGED_IN", comment: "Error - User logged in")
        showAlert = true
        
        /*presentError(alertMessage) {
            //Alert Dialog Box completion handler
            self.dismissView()
        }*/
        CustomAlert.show(message: alertMessage, primaryAction: {
            self.dismissView()
        })
    }
    
    private func invalidQRCodeErrorDimissView() {
        Logs.Print("Invalid QR Code, and should not be able to register")
        alertMessage = NSLocalizedString("ERROR_INVALID_QR", comment: "Error - Invalid QR Code")
        showAlert = true
        
        /*presentError(alertMessage) {
            self.dismissView()
        }*/
        CustomAlert.show(message: alertMessage, primaryAction: {
            self.dismissView()
        })
    }
    
    private func qrCodeVerified(_ code: ScannerDir) {
        Logs.Print("qrCodeVerified complete")
        Logs.Print("fromVC.notification \(fromVC.notification)")
        Logs.Print("code.viewController \(code.viewController)")
        
        dismissView()
        
        if fromVC.notification == .navigateFromScannerDashboard {
            Logs.Print("Scanner from dashboard ~ \(fromVC.notification)")
            NotificationCenter.default.post(name: fromVC.notification, object: nil, userInfo: ["": code.viewController])
        } else {
            Logs.Print("Scanner from user have not logged in ~ \(fromVC.notification)")
            NotificationCenter.default.post(name: fromVC.notification, object: nil, userInfo: ["": code.viewController])
        }
    }
    
    private func handleMyDIDScannedCode(_ jsonStruct: String) {
        NotificationCenter.default.postNotificationNameAsync(.showLoadingOverlay, object: nil)
        
        MyDIDCreds.initiateMyDID(jsonStruct) { result, message, code in
            DispatchQueue.main.async {
                if result {
                    if let image = SPassImages.push_noti {
                        CustomAlert.show(type: .success, message: NSLocalizedString("TEXT_MYDID_PUSH_NOTIFICATION", comment: "Text - MyDID notification sent"), images: [image], primaryAction: {
                            NotificationCenter.default.postNotificationNameAsync(.hideLoadingOverlay, object: nil)
                            self.dismissView()
                        })
                    } else {
                        CustomAlert.show(type: .success, message: NSLocalizedString("TEXT_MYDID_PUSH_NOTIFICATION", comment: "Text - MyDID notification sent"), primaryAction: {
                            NotificationCenter.default.postNotificationNameAsync(.hideLoadingOverlay, object: nil)
                            self.dismissView()
                        })
                    }
                } else {
                    CustomAlert.show(type: .cancel, message: message ?? NSLocalizedString("TEXT_MYDID_ACCOUNT_NOT_FOUND", comment: "Text - MyDigital ID account not found"), code: code, primaryAction: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            NotificationCenter.default.postNotificationNameAsync(.hideLoadingOverlay, object: nil)
                            
                            if !SPassDetails.isAppAvailable(for: "misignet://") {
                                CustomAlert.show(message: String(format: NSLocalizedString("TEXT_APP_UNAVAILABLE_MESSAGE", comment: "Text - Application is not installed on your device"), "MyDigital ID"), primaryAction: {
                                    if let url = URL(string: "https://apps.apple.com/my/app/mydigital-id/id1435289143") {
                                        UIApplication.shared.open(url)
                                    }
                                    self.dismissView()
                                })
                            } else {
                                switch code {
                                case MyDIDCode.noCert.code, MyDIDCode.revokedCert.code:
                                    MiSignetHelper.requestOnboarding(name: UserProfile.shared.userBio.fullname, ic: UserProfile.shared.userBio.currICNum, errorHandler: { error in
                                        Logs.Print("\(error)")
                                    })
                                    
                                default:
                                    if let url = URL(string:"misignet://") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                
                                self.dismissView()
                            }
                        }
                    }, secondaryAction: {
                        NotificationCenter.default.postNotificationNameAsync(.hideLoadingOverlay, object: nil)
                        self.dismissView()
                    })
                    
                }
            }
        }
    }
}

