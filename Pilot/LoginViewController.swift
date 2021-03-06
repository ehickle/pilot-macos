//
//  LoginViewController.swift
//  Pilot
//
//  Created by Rohan Nagar on 10/18/15.
//  Copyright © 2015 Sanction. All rights reserved.
//

import Cocoa
import HTTPStatusCodes
import SwiftyJSON
import FileKit
import Locksmith

class LoginViewController: NSViewController, SignInDelegate {

  @IBOutlet weak var signInButton: NSButton!
  @IBOutlet weak var iconView: NSImageView!
  @IBOutlet weak var emailTextField: NSTextField!
  @IBOutlet weak var passwordTextField: NSSecureTextField!
  @IBOutlet weak var message: NSTextField!

  var userService = PilotUserService()

  let defaults = UserDefaults.standard

  override func viewDidLoad() {
    super.viewDidLoad()
    
    self.view.wantsLayer = true
    
    // Disable window resize for the login window
    self.preferredContentSize = NSMakeSize(self.view.frame.size.width, self.view.frame.size.height);

    // Set the app icon image
    iconView.image = NSImage(named: "LoginIcon")

    // Change the textfield text color to custom pilot brown 
    emailTextField.textColor = PilotColors.PilotBrownText
    passwordTextField.textColor = PilotColors.PilotBrownText
  }
  
  override func awakeFromNib() {
    if self.view.layer != nil {
      self.view.layer?.backgroundColor = PilotColors.White.cgColor
    }
  }
  
  override func viewDidAppear() {
    self.view.window!.backgroundColor = PilotColors.White
    
    self.view.window!.titleVisibility = NSWindowTitleVisibility.hidden
    self.view.window!.titlebarAppearsTransparent = true
  }

  /// Called when `emailTextField` sends an action.
  ///
  /// - parameters
  ///   - sender: The `NSTextField` object that sent the action.
  ///
  @IBAction func didEndEmailEditing(_ sender: NSTextField) {
    if sender != emailTextField {
      return
    }

    passwordTextField.becomeFirstResponder()
  }

  /// Called when `passwordTextField sends an action.
  ///
  /// - parameters:
  ///    - sender: The `NSSecureTextField` object that sent the action.
  ///
  @IBAction func didEndPasswordEditing(_ sender: NSSecureTextField) {
    if sender != passwordTextField {
      return
    }

    passwordTextField.resignFirstResponder()
    signInButton(sender)
  }

  /// Called when the sign in button is pressed.
  ///
  /// - parameters:
  ///    - sender: The object that send the action.
  ///
  @IBAction func signInButton(_ sender: AnyObject) {
    if emailTextField.stringValue == "" || passwordTextField.stringValue == "" {
      message.stringValue = "Cannot have an empty email or password field."
      return
    }

    signIn(self.view.window!, email: emailTextField.stringValue, password: passwordTextField.stringValue)
  }

  @IBAction func signUp(_ sender: Any) {
    let signUpViewController = SignUpViewController()
    signUpViewController.signInDelegate = self

    self.view.window!.contentViewController = signUpViewController
  }

  func signIn(_ window: NSWindow, email: String, password: String) {
    let hashedPassword = PasswordService.hashPassword(password)

    // Get the requested Pilot user
    userService.getPilotUser(email, password: hashedPassword,
      completion: { user in
        // Store the email in NSUserDefaults as the existingUser
        self.defaults.set(user.email, forKey: "existingUser")

        // Attempt to store the password for that user in KeyChain
        do {
          try Locksmith.saveData(data: ["password": password], forUserAccount: user.email)
        } catch LocksmithError.duplicate {
          print("Duplicate with Locksmith")
        } catch {
          print("There was an error with Locksmith")
        }

        // Set up the MainViewController
        guard let mainViewController = MainViewController(nibName: "MainViewController", bundle: nil) else {
          return
        }

        // Set up the ErrorController class
        let errorController = ErrorController(viewController: mainViewController)
        ErrorController.sharedErrorController = errorController

        // Set the current user in the mainViewController
        mainViewController.loadUser(user)

        // Load the prefrences for the user
        let preferences = self.fetchPreferences(user)
        mainViewController.loadUserPreferences(preferences)

        // Determine the users platforms and add them to mainViewController
        if user.facebookAccessToken != nil {
          mainViewController.addPlatform(Platform(title: "Facebook", icon: NSImage(named: "FacebookIcon"), type: .facebook))

          // Set up and load the FacebookService class
          let facebookService = FacebookService(preferences: preferences, pilotUser: user)

          // Set the FileSystemWatcher class for facebook
          facebookService.setFileSystemWatcher(mainViewController)

          // Attempt to grab facebook cloud files and call the DirectoryService
          facebookService.refreshCachedLocalContent()

          // Load the facebookService class for current user
          mainViewController.loadFacebookService(facebookService)
        }

        if user.twitterAccessToken != nil {
          mainViewController.addPlatform(Platform(title: "Twitter", icon: NSImage(named: "TwitterIcon"), type: PlatformType.twitter))

          // Eventually load twitterService here
        }

        // Enable window resize for mainViewController
        // window.styleMask |= NSResizableWindowMask

        // Present the MainViewController to the user
        window.contentViewController = mainViewController
      },
      failure: { statusCode in
        switch statusCode {
        case HTTPStatusCode.unauthorized:
          self.message.stringValue = "Invalid authentication credentials."
        case HTTPStatusCode.badRequest:
          self.message.stringValue = "Bad input, please fix and try again."
        case HTTPStatusCode.notFound:
          self.message.stringValue = "Unable to find email in database. Please try again or sign up."
        case HTTPStatusCode.internalServerError:
          self.message.stringValue = "Unable to connect to database. Please file a report and try again later."
        default:
          self.message.stringValue = "WTF"
        }
      })
  }

  func cancel(window: NSWindow) {
    window.contentViewController = self
  }

  func fetchPreferences(_ user: PilotUser) -> Preferences {
    // Grab the raw JSON from userDefualts as a String
    if let rawStringJSON = self.defaults.object(forKey: user.email) as? String {

      // Creat a JSON object and convert it to an object of type Preferences
      return Preferences.fromJSON(JSON.parse(rawStringJSON))
    }

    // If that failes register default preferences
    return self.registerDefaultPreferences(user)
  }

  func registerDefaultPreferences(_ user: PilotUser) -> Preferences {
    let updatePreferences = Preferences(rootPath: "\(Path.userHome)/pilot/\(user.email)/")

    Preferences.updatePreferences(updatePreferences, email: user.email)

    return updatePreferences
  }

}
