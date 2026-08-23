import 'install_prompt.dart';

/// Anywhere that is not a browser. See [InstallPrompt].
InstallPrompt installPromptForPlatform() => const AbsentInstallPrompt();
