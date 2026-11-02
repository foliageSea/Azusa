import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Azusa'**
  String get appTitle;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @components.
  ///
  /// In en, this message translates to:
  /// **'Components'**
  String get components;

  /// No description provided for @examples.
  ///
  /// In en, this message translates to:
  /// **'Examples'**
  String get examples;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore components'**
  String get explore;

  /// No description provided for @openTasks.
  ///
  /// In en, this message translates to:
  /// **'Open task workspace'**
  String get openTasks;

  /// No description provided for @allTasks.
  ///
  /// In en, this message translates to:
  /// **'All tasks'**
  String get allTasks;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get pending;

  /// No description provided for @taskWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Task workspace'**
  String get taskWorkspace;

  /// No description provided for @newTask.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get newTask;

  /// No description provided for @editTask.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTask;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get dueDate;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @requiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter a title.'**
  String get requiredTitle;

  /// No description provided for @searchTasks.
  ///
  /// In en, this message translates to:
  /// **'Search tasks…'**
  String get searchTasks;

  /// No description provided for @emptyTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet'**
  String get emptyTasks;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No matching results'**
  String get noResults;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @deleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this task?'**
  String get deleteTitle;

  /// No description provided for @deleteBody.
  ///
  /// In en, this message translates to:
  /// **'This task will be removed from this device.'**
  String get deleteBody;

  /// No description provided for @noDate.
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get noDate;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something needs attention'**
  String get errorTitle;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @storageError.
  ///
  /// In en, this message translates to:
  /// **'Could not save or read local data. Your current input is preserved. Please try again.'**
  String get storageError;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Connection failed. Check your network and try again.'**
  String get networkError;

  /// No description provided for @timeoutError.
  ///
  /// In en, this message translates to:
  /// **'The request timed out. Please try again.'**
  String get timeoutError;

  /// No description provided for @serverError.
  ///
  /// In en, this message translates to:
  /// **'The server returned an error. Please try again.'**
  String get serverError;

  /// No description provided for @invalidDataError.
  ///
  /// In en, this message translates to:
  /// **'The response or configuration is invalid.'**
  String get invalidDataError;

  /// No description provided for @cancelledError.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled.'**
  String get cancelledError;

  /// No description provided for @searchComponents.
  ///
  /// In en, this message translates to:
  /// **'Search components…'**
  String get searchComponents;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @basic.
  ///
  /// In en, this message translates to:
  /// **'Essentials'**
  String get basic;

  /// No description provided for @input.
  ///
  /// In en, this message translates to:
  /// **'Forms'**
  String get input;

  /// No description provided for @content.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get content;

  /// No description provided for @navigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navigation;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Live preview'**
  String get preview;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get source;

  /// No description provided for @copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @documentation.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get documentation;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @defaultState.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultState;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selected;

  /// No description provided for @action.
  ///
  /// In en, this message translates to:
  /// **'Try it'**
  String get action;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @sampleText.
  ///
  /// In en, this message translates to:
  /// **'Make room for good ideas.'**
  String get sampleText;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get emailInvalid;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @submitted.
  ///
  /// In en, this message translates to:
  /// **'Form submitted'**
  String get submitted;

  /// No description provided for @optionA.
  ///
  /// In en, this message translates to:
  /// **'Design'**
  String get optionA;

  /// No description provided for @optionB.
  ///
  /// In en, this message translates to:
  /// **'Develop'**
  String get optionB;

  /// No description provided for @optionC.
  ///
  /// In en, this message translates to:
  /// **'Ship'**
  String get optionC;

  /// No description provided for @openOverlay.
  ///
  /// In en, this message translates to:
  /// **'Open overlay'**
  String get openOverlay;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSize;

  /// No description provided for @fontSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get fontSizeSmall;

  /// No description provided for @fontSizeStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get fontSizeStandard;

  /// No description provided for @fontSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get fontSizeLarge;

  /// No description provided for @fontSizePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get fontSizePreview;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @namingLanguage.
  ///
  /// In en, this message translates to:
  /// **'Naming language'**
  String get namingLanguage;

  /// No description provided for @organizeSeries.
  ///
  /// In en, this message translates to:
  /// **'Organize media'**
  String get organizeSeries;

  /// No description provided for @sortDirectory.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortDirectory;

  /// No description provided for @viewOnTmdb.
  ///
  /// In en, this message translates to:
  /// **'View on TMDB'**
  String get viewOnTmdb;

  /// No description provided for @sortName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortName;

  /// No description provided for @sortModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get sortModified;

  /// No description provided for @sortSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sortSize;

  /// No description provided for @sortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sortAscending;

  /// No description provided for @sortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sortDescending;

  /// No description provided for @parentDirectories.
  ///
  /// In en, this message translates to:
  /// **'Parent directories'**
  String get parentDirectories;

  /// No description provided for @sortNameAscending.
  ///
  /// In en, this message translates to:
  /// **'Name: A to Z'**
  String get sortNameAscending;

  /// No description provided for @sortNameDescending.
  ///
  /// In en, this message translates to:
  /// **'Name: Z to A'**
  String get sortNameDescending;

  /// No description provided for @sortModifiedDescending.
  ///
  /// In en, this message translates to:
  /// **'Modified: newest first'**
  String get sortModifiedDescending;

  /// No description provided for @sortModifiedAscending.
  ///
  /// In en, this message translates to:
  /// **'Modified: oldest first'**
  String get sortModifiedAscending;

  /// No description provided for @sortSizeDescending.
  ///
  /// In en, this message translates to:
  /// **'Size: largest first'**
  String get sortSizeDescending;

  /// No description provided for @sortSizeAscending.
  ///
  /// In en, this message translates to:
  /// **'Size: smallest first'**
  String get sortSizeAscending;

  /// No description provided for @sortSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save sort settings. Try again'**
  String get sortSaveFailed;

  /// No description provided for @executionHistory.
  ///
  /// In en, this message translates to:
  /// **'Execution history'**
  String get executionHistory;

  /// No description provided for @aiUsage.
  ///
  /// In en, this message translates to:
  /// **'AI usage'**
  String get aiUsage;

  /// No description provided for @switchLight.
  ///
  /// In en, this message translates to:
  /// **'Switch to light mode'**
  String get switchLight;

  /// No description provided for @switchDark.
  ///
  /// In en, this message translates to:
  /// **'Switch to dark mode'**
  String get switchDark;

  /// No description provided for @minimizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimizeWindow;

  /// No description provided for @maximizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Maximize / Restore'**
  String get maximizeWindow;

  /// No description provided for @previousStep.
  ///
  /// In en, this message translates to:
  /// **'Back to previous step'**
  String get previousStep;

  /// No description provided for @saveThemeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save theme. Please try again.'**
  String get saveThemeFailed;

  /// No description provided for @webdavUrl.
  ///
  /// In en, this message translates to:
  /// **'WebDAV URL'**
  String get webdavUrl;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @aiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible API base URL'**
  String get aiBaseUrl;

  /// No description provided for @modelName.
  ///
  /// In en, this message translates to:
  /// **'Model name'**
  String get modelName;

  /// No description provided for @testWebdav.
  ///
  /// In en, this message translates to:
  /// **'Test WebDAV'**
  String get testWebdav;

  /// No description provided for @testAi.
  ///
  /// In en, this message translates to:
  /// **'Test AI'**
  String get testAi;

  /// No description provided for @testTmdb.
  ///
  /// In en, this message translates to:
  /// **'Test TMDB'**
  String get testTmdb;

  /// No description provided for @saveConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Save configuration'**
  String get saveConfiguration;

  /// No description provided for @configurationSaved.
  ///
  /// In en, this message translates to:
  /// **'Configuration saved'**
  String get configurationSaved;

  /// No description provided for @httpProxy.
  ///
  /// In en, this message translates to:
  /// **'HTTP proxy'**
  String get httpProxy;

  /// No description provided for @proxyMode.
  ///
  /// In en, this message translates to:
  /// **'Proxy mode'**
  String get proxyMode;

  /// No description provided for @directConnection.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get directConnection;

  /// No description provided for @systemProxyMode.
  ///
  /// In en, this message translates to:
  /// **'System proxy'**
  String get systemProxyMode;

  /// No description provided for @manualProxyMode.
  ///
  /// In en, this message translates to:
  /// **'Manual proxy'**
  String get manualProxyMode;

  /// No description provided for @proxyAddress.
  ///
  /// In en, this message translates to:
  /// **'Proxy URL (http://host:port)'**
  String get proxyAddress;

  /// No description provided for @proxyAi.
  ///
  /// In en, this message translates to:
  /// **'Use proxy for AI'**
  String get proxyAi;

  /// No description provided for @proxyTmdb.
  ///
  /// In en, this message translates to:
  /// **'Use proxy for TMDB'**
  String get proxyTmdb;

  /// No description provided for @proxyWebdav.
  ///
  /// In en, this message translates to:
  /// **'Use proxy for WebDAV'**
  String get proxyWebdav;

  /// No description provided for @appAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get appAbout;

  /// No description provided for @misansLicense.
  ///
  /// In en, this message translates to:
  /// **'MiSans font license'**
  String get misansLicense;

  /// No description provided for @tmdbDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'This product uses the TMDB API but is not endorsed or certified by TMDB.'**
  String get tmdbDisclaimer;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {error}'**
  String saveFailed(String error);

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String connectionFailed(String error);

  /// No description provided for @configurationLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load configuration: {error}'**
  String configurationLoadFailed(String error);

  /// No description provided for @connectionSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Connected · {route}'**
  String connectionSucceeded(String route);

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @information.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get information;

  /// No description provided for @noticeError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get noticeError;

  /// No description provided for @favoriteSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save favorites. Please try again.'**
  String get favoriteSaveFailed;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @favoritesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load favorites'**
  String get favoritesLoadFailed;

  /// No description provided for @noFavorites.
  ///
  /// In en, this message translates to:
  /// **'No favorite directories'**
  String get noFavorites;

  /// No description provided for @removeFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove favorite {path}'**
  String removeFavorite(String path);

  /// No description provided for @confirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmAction;

  /// No description provided for @analyzeDirectory.
  ///
  /// In en, this message translates to:
  /// **'Send this directory to AI for analysis?'**
  String get analyzeDirectory;

  /// No description provided for @analyzeDirectoryDetail.
  ///
  /// In en, this message translates to:
  /// **'Paths and file names in the selected directory and its immediate subfolders will be sent to your configured AI service. File contents will not be uploaded.'**
  String get analyzeDirectoryDetail;

  /// No description provided for @startAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Start analysis'**
  String get startAnalysis;

  /// No description provided for @executeRenames.
  ///
  /// In en, this message translates to:
  /// **'Execute selected renames?'**
  String get executeRenames;

  /// No description provided for @executeRenamesDetail.
  ///
  /// In en, this message translates to:
  /// **'Files will be renamed as previewed. Files in subfolders will move into the selected directory; original subfolders remain. Execution stops on failure and never overwrites existing files.'**
  String get executeRenamesDetail;

  /// No description provided for @startExecution.
  ///
  /// In en, this message translates to:
  /// **'Start execution'**
  String get startExecution;

  /// No description provided for @configureConnection.
  ///
  /// In en, this message translates to:
  /// **'Configure connection'**
  String get configureConnection;

  /// No description provided for @noConnectionConfigured.
  ///
  /// In en, this message translates to:
  /// **'No NAS connection configured. Set up WebDAV, AI, and TMDB credentials first.'**
  String get noConnectionConfigured;

  /// No description provided for @executionSafety.
  ///
  /// In en, this message translates to:
  /// **'Rename one by one, stop on failure, and never overwrite existing files.'**
  String get executionSafety;

  /// No description provided for @confirmAndExecute.
  ///
  /// In en, this message translates to:
  /// **'Confirm and execute'**
  String get confirmAndExecute;

  /// No description provided for @organizeDirectory.
  ///
  /// In en, this message translates to:
  /// **'Organize this directory'**
  String get organizeDirectory;

  /// No description provided for @parentDirectory.
  ///
  /// In en, this message translates to:
  /// **'Parent directory'**
  String get parentDirectory;

  /// No description provided for @refreshDirectory.
  ///
  /// In en, this message translates to:
  /// **'Refresh directory'**
  String get refreshDirectory;

  /// No description provided for @unfavoriteDirectory.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite current directory'**
  String get unfavoriteDirectory;

  /// No description provided for @favoriteDirectory.
  ///
  /// In en, this message translates to:
  /// **'Favorite current directory'**
  String get favoriteDirectory;

  /// No description provided for @nasDirectory.
  ///
  /// In en, this message translates to:
  /// **'NAS directory'**
  String get nasDirectory;

  /// No description provided for @organizingRequirements.
  ///
  /// In en, this message translates to:
  /// **'Organizing requirements'**
  String get organizingRequirements;

  /// No description provided for @renamePreview.
  ///
  /// In en, this message translates to:
  /// **'Rename preview'**
  String get renamePreview;

  /// No description provided for @renaming.
  ///
  /// In en, this message translates to:
  /// **'Renaming files'**
  String get renaming;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get processing;

  /// No description provided for @rootDirectory.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get rootDirectory;

  /// No description provided for @directoryCounts.
  ///
  /// In en, this message translates to:
  /// **'{folders} folders · {files} files'**
  String directoryCounts(int folders, int files);

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @connectNas.
  ///
  /// In en, this message translates to:
  /// **'Connect NAS'**
  String get connectNas;

  /// No description provided for @filterByName.
  ///
  /// In en, this message translates to:
  /// **'Filter by name'**
  String get filterByName;

  /// No description provided for @browseNasHint.
  ///
  /// In en, this message translates to:
  /// **'Connect to your NAS to browse and open the media directory you want to organize.'**
  String get browseNasHint;

  /// No description provided for @directoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'This directory is empty'**
  String get directoryEmpty;

  /// No description provided for @noNameMatches.
  ///
  /// In en, this message translates to:
  /// **'No items contain “{query}”'**
  String noNameMatches(String query);

  /// No description provided for @openSeriesDirectory.
  ///
  /// In en, this message translates to:
  /// **'Connect to your NAS and open a movie or series directory first.'**
  String get openSeriesDirectory;

  /// No description provided for @openNonemptyDirectory.
  ///
  /// In en, this message translates to:
  /// **'This directory has no files. Open a directory containing movies or episodes.'**
  String get openNonemptyDirectory;

  /// No description provided for @aiSuggestions.
  ///
  /// In en, this message translates to:
  /// **'AI organizing suggestions'**
  String get aiSuggestions;

  /// No description provided for @optionalRequirements.
  ///
  /// In en, this message translates to:
  /// **'Organizing requirements (optional)'**
  String get optionalRequirements;

  /// No description provided for @requirementsHint.
  ///
  /// In en, this message translates to:
  /// **'Movie / series title, year / season, TMDB ID, or naming preferences'**
  String get requirementsHint;

  /// No description provided for @generateSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Generate rename suggestions'**
  String get generateSuggestions;

  /// No description provided for @viewRenamePreview.
  ///
  /// In en, this message translates to:
  /// **'View rename preview'**
  String get viewRenamePreview;

  /// No description provided for @noPendingChanges.
  ///
  /// In en, this message translates to:
  /// **'No pending changes'**
  String get noPendingChanges;

  /// No description provided for @backToRequirements.
  ///
  /// In en, this message translates to:
  /// **'Back to requirements'**
  String get backToRequirements;

  /// No description provided for @backToNasDirectory.
  ///
  /// In en, this message translates to:
  /// **'Back to NAS directory'**
  String get backToNasDirectory;

  /// No description provided for @selectedChanges.
  ///
  /// In en, this message translates to:
  /// **'{selected} / {total} selected · {changes} changes'**
  String selectedChanges(int selected, int total, int changes);

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @cannotExecute.
  ///
  /// In en, this message translates to:
  /// **'Cannot execute yet'**
  String get cannotExecute;

  /// No description provided for @inputTokens.
  ///
  /// In en, this message translates to:
  /// **'Input tokens'**
  String get inputTokens;

  /// No description provided for @outputTokens.
  ///
  /// In en, this message translates to:
  /// **'Output tokens'**
  String get outputTokens;

  /// No description provided for @averageTps.
  ///
  /// In en, this message translates to:
  /// **'Average TPS'**
  String get averageTps;

  /// No description provided for @estimatedCost.
  ///
  /// In en, this message translates to:
  /// **'Estimated cost'**
  String get estimatedCost;

  /// No description provided for @analysisUsage.
  ///
  /// In en, this message translates to:
  /// **'AI analysis usage'**
  String get analysisUsage;

  /// No description provided for @folder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// No description provided for @openEntry.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String openEntry(String name);

  /// No description provided for @pendingRenameShort.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pendingRenameShort;

  /// No description provided for @pendingRename.
  ///
  /// In en, this message translates to:
  /// **'Pending rename'**
  String get pendingRename;

  /// No description provided for @unchanged.
  ///
  /// In en, this message translates to:
  /// **'Unchanged'**
  String get unchanged;

  /// No description provided for @newFileName.
  ///
  /// In en, this message translates to:
  /// **'New file name'**
  String get newFileName;

  /// No description provided for @renameEntry.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameEntry;

  /// No description provided for @entryActions.
  ///
  /// In en, this message translates to:
  /// **'More actions for {name}'**
  String entryActions(String name);

  /// No description provided for @usageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load AI usage'**
  String get usageLoadFailed;

  /// No description provided for @analysisCount.
  ///
  /// In en, this message translates to:
  /// **'Analyses'**
  String get analysisCount;

  /// No description provided for @modelRequests.
  ///
  /// In en, this message translates to:
  /// **'Model requests'**
  String get modelRequests;

  /// No description provided for @totalInputTokens.
  ///
  /// In en, this message translates to:
  /// **'Total input tokens'**
  String get totalInputTokens;

  /// No description provided for @totalOutputTokens.
  ///
  /// In en, this message translates to:
  /// **'Total output tokens'**
  String get totalOutputTokens;

  /// No description provided for @totalEstimatedCost.
  ///
  /// In en, this message translates to:
  /// **'Estimated total cost (USD)'**
  String get totalEstimatedCost;

  /// No description provided for @analysisHistory.
  ///
  /// In en, this message translates to:
  /// **'Analysis history'**
  String get analysisHistory;

  /// No description provided for @incompleteUsageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} with incomplete usage'**
  String incompleteUsageCount(int count);

  /// No description provided for @unknownCostCount.
  ///
  /// In en, this message translates to:
  /// **'{count} with unknown cost'**
  String unknownCostCount(int count);

  /// No description provided for @noAiUsage.
  ///
  /// In en, this message translates to:
  /// **'No AI analysis usage yet'**
  String get noAiUsage;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @usageInput.
  ///
  /// In en, this message translates to:
  /// **'Input {tokens} tokens'**
  String usageInput(String tokens);

  /// No description provided for @usageOutput.
  ///
  /// In en, this message translates to:
  /// **'Output {tokens} tokens'**
  String usageOutput(String tokens);

  /// No description provided for @unknownCost.
  ///
  /// In en, this message translates to:
  /// **'Cost —'**
  String get unknownCost;

  /// No description provided for @modelRequestCount.
  ///
  /// In en, this message translates to:
  /// **'{count} model requests'**
  String modelRequestCount(int count);

  /// No description provided for @historyLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load history: {error}'**
  String historyLoadFailed(String error);

  /// No description provided for @noExecutionHistory.
  ///
  /// In en, this message translates to:
  /// **'No execution history yet'**
  String get noExecutionHistory;

  /// No description provided for @operationCount.
  ///
  /// In en, this message translates to:
  /// **'{count} operations'**
  String operationCount(int count);

  /// No description provided for @otherRecords.
  ///
  /// In en, this message translates to:
  /// **'Other records'**
  String get otherRecords;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @initiated.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get initiated;

  /// No description provided for @collapseHistory.
  ///
  /// In en, this message translates to:
  /// **'Collapse record details'**
  String get collapseHistory;

  /// No description provided for @expandHistory.
  ///
  /// In en, this message translates to:
  /// **'Expand record details'**
  String get expandHistory;

  /// No description provided for @startedAtTime.
  ///
  /// In en, this message translates to:
  /// **'Started at {time}'**
  String startedAtTime(String time);

  /// No description provided for @renameAction.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameAction;

  /// No description provided for @moveAction.
  ///
  /// In en, this message translates to:
  /// **'Move / Rename'**
  String get moveAction;

  /// No description provided for @uploadAction.
  ///
  /// In en, this message translates to:
  /// **'Upload file'**
  String get uploadAction;

  /// No description provided for @createDirectory.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get createDirectory;

  /// No description provided for @operationRecord.
  ///
  /// In en, this message translates to:
  /// **'Operation record'**
  String get operationRecord;

  /// No description provided for @invalidDirectoryPath.
  ///
  /// In en, this message translates to:
  /// **'Invalid directory path'**
  String get invalidDirectoryPath;

  /// No description provided for @favoriteOutsideRoot.
  ///
  /// In en, this message translates to:
  /// **'The favorite directory is outside the NAS root'**
  String get favoriteOutsideRoot;

  /// No description provided for @webdavUrlParameters.
  ///
  /// In en, this message translates to:
  /// **'The WebDAV URL cannot contain query parameters'**
  String get webdavUrlParameters;

  /// No description provided for @pathOutsideConnection.
  ///
  /// In en, this message translates to:
  /// **'The path is outside the WebDAV connection directory'**
  String get pathOutsideConnection;

  /// No description provided for @invalidWebdavProperties.
  ///
  /// In en, this message translates to:
  /// **'WebDAV did not return valid file properties'**
  String get invalidWebdavProperties;

  /// No description provided for @unknownFileStatus.
  ///
  /// In en, this message translates to:
  /// **'Could not determine file status. Check WebDAV permissions'**
  String get unknownFileStatus;

  /// No description provided for @moveUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Move was not confirmed. Refresh the directory to verify'**
  String get moveUnconfirmed;

  /// No description provided for @directoryCreationUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Directory creation was not confirmed'**
  String get directoryCreationUnconfirmed;

  /// No description provided for @deleteUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Deletion was not confirmed. Refresh the directory to verify'**
  String get deleteUnconfirmed;

  /// No description provided for @uploadUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Upload was not confirmed. Refresh the directory to verify'**
  String get uploadUnconfirmed;

  /// No description provided for @absoluteWebdavPathRequired.
  ///
  /// In en, this message translates to:
  /// **'WebDAV paths must be absolute'**
  String get absoluteWebdavPathRequired;

  /// No description provided for @unsafeWebdavPath.
  ///
  /// In en, this message translates to:
  /// **'The WebDAV path contains unsafe characters'**
  String get unsafeWebdavPath;

  /// No description provided for @networkClientClosed.
  ///
  /// In en, this message translates to:
  /// **'Network client is closed'**
  String get networkClientClosed;

  /// No description provided for @systemProxyTimeout.
  ///
  /// In en, this message translates to:
  /// **'Reading the system proxy timed out'**
  String get systemProxyTimeout;

  /// No description provided for @invalidSystemProxy.
  ///
  /// In en, this message translates to:
  /// **'The system proxy returned no valid configuration'**
  String get invalidSystemProxy;

  /// No description provided for @systemProxyUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Reading the system proxy is not supported on this platform'**
  String get systemProxyUnsupported;

  /// No description provided for @systemProxyReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the system proxy'**
  String get systemProxyReadFailed;

  /// No description provided for @environmentProxyUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Environment proxies must be unauthenticated HTTP proxies'**
  String get environmentProxyUnsupported;

  /// No description provided for @systemProxyTypeUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The system proxy type is unsupported. Only unauthenticated HTTP proxies are supported'**
  String get systemProxyTypeUnsupported;

  /// No description provided for @databaseClosed.
  ///
  /// In en, this message translates to:
  /// **'Database is closed'**
  String get databaseClosed;

  /// No description provided for @databaseVersionTooNew.
  ///
  /// In en, this message translates to:
  /// **'The database version is too new'**
  String get databaseVersionTooNew;

  /// No description provided for @targetFileExists.
  ///
  /// In en, this message translates to:
  /// **'The target file already exists'**
  String get targetFileExists;

  /// No description provided for @queryingMetadata.
  ///
  /// In en, this message translates to:
  /// **'Looking up movie and series metadata…'**
  String get queryingMetadata;

  /// No description provided for @suggestionsGenerated.
  ///
  /// In en, this message translates to:
  /// **'Suggestions generated'**
  String get suggestionsGenerated;

  /// No description provided for @noReliableSuggestions.
  ///
  /// In en, this message translates to:
  /// **'No reliable rename suggestions found. Add a movie title and year or a series name and season, then try again.'**
  String get noReliableSuggestions;

  /// No description provided for @usageSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save AI usage'**
  String get usageSaveFailed;

  /// No description provided for @operationCompleted.
  ///
  /// In en, this message translates to:
  /// **'Operation completed'**
  String get operationCompleted;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get downloading;

  /// No description provided for @downloadCompleted.
  ///
  /// In en, this message translates to:
  /// **'Download complete'**
  String get downloadCompleted;

  /// No description provided for @preparingExecution.
  ///
  /// In en, this message translates to:
  /// **'Preparing execution'**
  String get preparingExecution;

  /// No description provided for @directoryReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read directory: {error}'**
  String directoryReadFailed(String error);

  /// No description provided for @suggestionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not generate suggestions: {error}'**
  String suggestionsFailed(String error);

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailed(String error);

  /// No description provided for @fileOperationStopped.
  ///
  /// In en, this message translates to:
  /// **'File operation stopped: {error}; refresh the directory to verify the results'**
  String fileOperationStopped(String error);

  /// No description provided for @executionStopped.
  ///
  /// In en, this message translates to:
  /// **'Execution stopped: {error}; refresh the directory to verify the results'**
  String executionStopped(String error);

  /// No description provided for @remainingExecutionStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped: {error}. Verify the results before confirming the remaining changes'**
  String remainingExecutionStopped(String error);

  /// No description provided for @completedItemCount.
  ///
  /// In en, this message translates to:
  /// **'Completed {count} items'**
  String completedItemCount(int count);

  /// No description provided for @aiAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'AI analysis ({count}/8)'**
  String aiAnalyzing(int count);

  /// No description provided for @queryingTool.
  ///
  /// In en, this message translates to:
  /// **'Querying: {name}'**
  String queryingTool(String name);

  /// No description provided for @matchEvidence.
  ///
  /// In en, this message translates to:
  /// **'Match: season {season}, episode {episode} · {title}\nTMDB {id}'**
  String matchEvidence(String season, String episode, String title, String id);

  /// No description provided for @authenticationFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed or access denied (HTTP {code})'**
  String authenticationFailed(String code);

  /// No description provided for @proxyAuthenticationUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The proxy requires authentication. Only unauthenticated HTTP proxies are supported'**
  String get proxyAuthenticationUnsupported;

  /// No description provided for @remoteFileChanged.
  ///
  /// In en, this message translates to:
  /// **'The file changed or the target exists. Refresh the directory to verify'**
  String get remoteFileChanged;

  /// No description provided for @rateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please try again later'**
  String get rateLimited;

  /// No description provided for @networkConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed or timed out. Check the service URL and HTTP proxy'**
  String get networkConnectionFailed;

  /// No description provided for @httpStatusError.
  ///
  /// In en, this message translates to:
  /// **'The service returned HTTP {code}'**
  String httpStatusError(String code);

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed. Please try again'**
  String get operationFailed;

  /// No description provided for @invalidServiceUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid HTTPS URL (WebDAV also supports HTTP)'**
  String get invalidServiceUrl;

  /// No description provided for @invalidProxyUrl.
  ///
  /// In en, this message translates to:
  /// **'Proxy URL must use http://host:port'**
  String get invalidProxyUrl;

  /// No description provided for @proxyUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a proxy URL'**
  String get proxyUrlRequired;

  /// No description provided for @invalidAiModels.
  ///
  /// In en, this message translates to:
  /// **'AI /models did not return valid JSON'**
  String get invalidAiModels;

  /// No description provided for @aiClientClosed.
  ///
  /// In en, this message translates to:
  /// **'AI client is closed'**
  String get aiClientClosed;

  /// No description provided for @aiAlreadyRunning.
  ///
  /// In en, this message translates to:
  /// **'AI analysis is already running'**
  String get aiAlreadyRunning;

  /// No description provided for @modelNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an AI model name'**
  String get modelNameRequired;

  /// No description provided for @tooManyFiles.
  ///
  /// In en, this message translates to:
  /// **'This directory contains more than 500 files. Select a smaller directory'**
  String get tooManyFiles;

  /// No description provided for @aiCallLimit.
  ///
  /// In en, this message translates to:
  /// **'AI tool call limit exceeded'**
  String get aiCallLimit;

  /// No description provided for @invalidAiSuggestions.
  ///
  /// In en, this message translates to:
  /// **'AI returned no valid suggestions or reached its execution limit'**
  String get invalidAiSuggestions;

  /// No description provided for @missingTmdbEvidence.
  ///
  /// In en, this message translates to:
  /// **'AI suggestions lack valid TMDB episode evidence. Please try again'**
  String get missingTmdbEvidence;

  /// No description provided for @tmdbTokenRequired.
  ///
  /// In en, this message translates to:
  /// **'Configure a TMDB token'**
  String get tmdbTokenRequired;

  /// No description provided for @invalidMovieQuery.
  ///
  /// In en, this message translates to:
  /// **'Invalid movie query'**
  String get invalidMovieQuery;

  /// No description provided for @invalidMovieId.
  ///
  /// In en, this message translates to:
  /// **'Invalid movie ID'**
  String get invalidMovieId;

  /// No description provided for @invalidMovieDetails.
  ///
  /// In en, this message translates to:
  /// **'Invalid TMDB movie details'**
  String get invalidMovieDetails;

  /// No description provided for @invalidMediaType.
  ///
  /// In en, this message translates to:
  /// **'The AI suggestion has an invalid media type. Try again'**
  String get invalidMediaType;

  /// No description provided for @missingMovieEvidence.
  ///
  /// In en, this message translates to:
  /// **'The AI suggestion has no verified TMDB movie evidence. Try again'**
  String get missingMovieEvidence;

  /// No description provided for @movieMatchEvidence.
  ///
  /// In en, this message translates to:
  /// **'Movie match: {title} · {date}\nTMDB {id}'**
  String movieMatchEvidence(String title, String date, String id);

  /// No description provided for @subtitleRenamedWithVideo.
  ///
  /// In en, this message translates to:
  /// **'Rename with video · {name}'**
  String subtitleRenamedWithVideo(String name);

  /// No description provided for @invalidSeriesQuery.
  ///
  /// In en, this message translates to:
  /// **'Invalid series query'**
  String get invalidSeriesQuery;

  /// No description provided for @invalidSeasonNumber.
  ///
  /// In en, this message translates to:
  /// **'Invalid series or season number'**
  String get invalidSeasonNumber;

  /// No description provided for @duplicateSource.
  ///
  /// In en, this message translates to:
  /// **'The same source file appears more than once'**
  String get duplicateSource;

  /// No description provided for @sourceAttributesChanged.
  ///
  /// In en, this message translates to:
  /// **'Source file attributes changed. Generate suggestions again'**
  String get sourceAttributesChanged;

  /// No description provided for @targetConflict.
  ///
  /// In en, this message translates to:
  /// **'The target conflicts with another pending file'**
  String get targetConflict;

  /// No description provided for @taskAlreadyRunning.
  ///
  /// In en, this message translates to:
  /// **'An organizing task is already running'**
  String get taskAlreadyRunning;

  /// No description provided for @sourceMissing.
  ///
  /// In en, this message translates to:
  /// **'The source file no longer exists'**
  String get sourceMissing;

  /// No description provided for @sourceChanged.
  ///
  /// In en, this message translates to:
  /// **'Source file attributes changed'**
  String get sourceChanged;

  /// No description provided for @targetExists.
  ///
  /// In en, this message translates to:
  /// **'The target already exists'**
  String get targetExists;

  /// No description provided for @rootModificationForbidden.
  ///
  /// In en, this message translates to:
  /// **'Cannot modify the WebDAV root directory'**
  String get rootModificationForbidden;

  /// No description provided for @moveIntoSelfForbidden.
  ///
  /// In en, this message translates to:
  /// **'Cannot move a directory inside itself'**
  String get moveIntoSelfForbidden;

  /// No description provided for @unsupportedFileOperation.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file operation'**
  String get unsupportedFileOperation;

  /// No description provided for @invalidFileNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Invalid file name: the name cannot be empty'**
  String get invalidFileNameEmpty;

  /// No description provided for @invalidFileNameControl.
  ///
  /// In en, this message translates to:
  /// **'Invalid file name: control characters are not allowed'**
  String get invalidFileNameControl;

  /// No description provided for @invalidFileNameEnding.
  ///
  /// In en, this message translates to:
  /// **'Invalid file name: cannot end with a space or period'**
  String get invalidFileNameEnding;

  /// No description provided for @invalidFileNameCharacters.
  ///
  /// In en, this message translates to:
  /// **'The file name contains invalid characters'**
  String get invalidFileNameCharacters;

  /// No description provided for @sourcePathChanged.
  ///
  /// In en, this message translates to:
  /// **'Source file changed: {path}'**
  String sourcePathChanged(String path);

  /// No description provided for @extensionRequired.
  ///
  /// In en, this message translates to:
  /// **'Keep the original extension: {extension}'**
  String extensionRequired(String extension);

  /// No description provided for @duplicateTargetName.
  ///
  /// In en, this message translates to:
  /// **'Duplicate target file name: {name}'**
  String duplicateTargetName(String name);

  /// No description provided for @targetNameExists.
  ///
  /// In en, this message translates to:
  /// **'Target already exists: {name}'**
  String targetNameExists(String name);

  /// No description provided for @invalidFileNameReserved.
  ///
  /// In en, this message translates to:
  /// **'Invalid file name: “{name}” is not allowed'**
  String invalidFileNameReserved(String name);

  /// No description provided for @invalidFileNameReplace.
  ///
  /// In en, this message translates to:
  /// **'Invalid file name: replace “{character}” with “{replacement}” or “-”'**
  String invalidFileNameReplace(String character, String replacement);

  /// No description provided for @compactSidebar.
  ///
  /// In en, this message translates to:
  /// **'Compact sidebar'**
  String get compactSidebar;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About this template'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Third-party notices'**
  String get openSourceLicenses;

  /// No description provided for @fonts.
  ///
  /// In en, this message translates to:
  /// **'Font notice'**
  String get fonts;

  /// No description provided for @fontNotice.
  ///
  /// In en, this message translates to:
  /// **'This app uses the MiSans font. © Xiaomi Technology Co., Ltd. Used under the MiSans Font Intellectual Property License Agreement.'**
  String get fontNotice;

  /// No description provided for @runtimeEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Runtime environment'**
  String get runtimeEnvironment;

  /// No description provided for @operatingSystem.
  ///
  /// In en, this message translates to:
  /// **'Operating system'**
  String get operatingSystem;

  /// No description provided for @systemVersion.
  ///
  /// In en, this message translates to:
  /// **'System version'**
  String get systemVersion;

  /// No description provided for @dartVersion.
  ///
  /// In en, this message translates to:
  /// **'Dart version'**
  String get dartVersion;

  /// No description provided for @buildMode.
  ///
  /// In en, this message translates to:
  /// **'Build mode'**
  String get buildMode;

  /// No description provided for @buildModeDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get buildModeDebug;

  /// No description provided for @buildModeProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get buildModeProfile;

  /// No description provided for @buildModeRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get buildModeRelease;

  /// No description provided for @processorCount.
  ///
  /// In en, this message translates to:
  /// **'Logical processors'**
  String get processorCount;

  /// No description provided for @windowSize.
  ///
  /// In en, this message translates to:
  /// **'Window size (logical pixels)'**
  String get windowSize;

  /// No description provided for @devicePixelRatio.
  ///
  /// In en, this message translates to:
  /// **'Device pixel ratio'**
  String get devicePixelRatio;

  /// No description provided for @systemLocale.
  ///
  /// In en, this message translates to:
  /// **'System locale'**
  String get systemLocale;

  /// No description provided for @appLocale.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appLocale;

  /// No description provided for @openDocs.
  ///
  /// In en, this message translates to:
  /// **'Forui documentation'**
  String get openDocs;

  /// No description provided for @linkError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link.'**
  String get linkError;

  /// No description provided for @networkDemo.
  ///
  /// In en, this message translates to:
  /// **'Network playground'**
  String get networkDemo;

  /// No description provided for @mockMode.
  ///
  /// In en, this message translates to:
  /// **'Offline mock'**
  String get mockMode;

  /// No description provided for @liveMode.
  ///
  /// In en, this message translates to:
  /// **'Live API'**
  String get liveMode;

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get empty;

  /// No description provided for @timeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get timeout;

  /// No description provided for @serverFailure.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get serverFailure;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @emptyNetwork.
  ///
  /// In en, this message translates to:
  /// **'The request succeeded with no items.'**
  String get emptyNetwork;

  /// No description provided for @tasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasks;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimize;

  /// No description provided for @maximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get maximize;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get notFound;

  /// No description provided for @goHome.
  ///
  /// In en, this message translates to:
  /// **'Go to overview'**
  String get goHome;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme color'**
  String get themeColor;

  /// No description provided for @radiusScale.
  ///
  /// In en, this message translates to:
  /// **'Corner radius scale'**
  String get radiusScale;

  /// No description provided for @colorNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get colorNeutral;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorBlue;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorGreen;

  /// No description provided for @colorViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get colorViolet;

  /// No description provided for @colorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorOrange;

  /// No description provided for @colorRose.
  ///
  /// In en, this message translates to:
  /// **'Rose'**
  String get colorRose;

  /// No description provided for @logs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logs;

  /// No description provided for @searchLogs.
  ///
  /// In en, this message translates to:
  /// **'Search logs…'**
  String get searchLogs;

  /// No description provided for @pauseLogs.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseLogs;

  /// No description provided for @resumeLogs.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeLogs;

  /// No description provided for @autoScrollLogs.
  ///
  /// In en, this message translates to:
  /// **'Auto-scroll'**
  String get autoScrollLogs;

  /// No description provided for @copyVisibleLogs.
  ///
  /// In en, this message translates to:
  /// **'Copy results'**
  String get copyVisibleLogs;

  /// No description provided for @copyLogEntry.
  ///
  /// In en, this message translates to:
  /// **'Copy log entry'**
  String get copyLogEntry;

  /// No description provided for @clearLogView.
  ///
  /// In en, this message translates to:
  /// **'Clear view'**
  String get clearLogView;

  /// No description provided for @noLiveLogs.
  ///
  /// In en, this message translates to:
  /// **'No logs to display'**
  String get noLiveLogs;

  /// No description provided for @logCopyError.
  ///
  /// In en, this message translates to:
  /// **'Could not copy logs. Please try again.'**
  String get logCopyError;

  /// No description provided for @logEntryCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry} other{{count} entries}}'**
  String logEntryCount(int count);

  /// No description provided for @exportLogs.
  ///
  /// In en, this message translates to:
  /// **'Export logs'**
  String get exportLogs;

  /// No description provided for @exportingLogs.
  ///
  /// In en, this message translates to:
  /// **'Exporting logs…'**
  String get exportingLogs;

  /// No description provided for @noLogsToExport.
  ///
  /// In en, this message translates to:
  /// **'No logs available to export.'**
  String get noLogsToExport;

  /// No description provided for @logsExported.
  ///
  /// In en, this message translates to:
  /// **'Log archive saved.'**
  String get logsExported;

  /// No description provided for @logsShared.
  ///
  /// In en, this message translates to:
  /// **'Log archive shared.'**
  String get logsShared;

  /// No description provided for @logShareOpened.
  ///
  /// In en, this message translates to:
  /// **'Log sharing opened. Complete the export in the system share sheet.'**
  String get logShareOpened;

  /// No description provided for @logExportError.
  ///
  /// In en, this message translates to:
  /// **'Could not export logs. Check available storage and try again.'**
  String get logExportError;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
