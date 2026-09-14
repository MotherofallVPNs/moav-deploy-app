import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/server_profile.dart';
import '../../security/key_service.dart';

/// Which credential the user chose on the add-server form.
enum AuthChoice { generateKey, importKey, password }

extension AuthChoiceX on AuthChoice {
  SshAuthMethod get method => switch (this) {
        AuthChoice.generateKey => SshAuthMethod.generatedKey,
        AuthChoice.importKey => SshAuthMethod.importedKey,
        AuthChoice.password => SshAuthMethod.password,
      };
}

/// Immutable form state. Secrets are held here only until the form is
/// submitted, then handed to the secure store and dropped.
class AddServerFormState {
  const AddServerFormState({
    this.label = '',
    this.host = '',
    this.port = '22',
    this.username = 'root',
    this.authChoice = AuthChoice.generateKey,
    this.importedKeyPem = '',
    this.password = '',
    this.generatedKey,
    this.submitting = false,
    this.error,
  });

  final String label;
  final String host;
  final String port;
  final String username;
  final AuthChoice authChoice;
  final String importedKeyPem;
  final String password;
  final Ed25519KeyMaterial? generatedKey;
  final bool submitting;
  final String? error;

  AddServerFormState copyWith({
    String? label,
    String? host,
    String? port,
    String? username,
    AuthChoice? authChoice,
    String? importedKeyPem,
    String? password,
    Ed25519KeyMaterial? generatedKey,
    bool clearGeneratedKey = false,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) =>
      AddServerFormState(
        label: label ?? this.label,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        authChoice: authChoice ?? this.authChoice,
        importedKeyPem: importedKeyPem ?? this.importedKeyPem,
        password: password ?? this.password,
        generatedKey:
            clearGeneratedKey ? null : (generatedKey ?? this.generatedKey),
        submitting: submitting ?? this.submitting,
        error: clearError ? null : (error ?? this.error),
      );

  int? get parsedPort {
    final p = int.tryParse(port.trim());
    if (p == null || p < 1 || p > 65535) return null;
    return p;
  }

  String? get hostError {
    final h = host.trim();
    if (h.isEmpty) return 'Host is required';
    if (h.contains(RegExp(r'\s'))) return 'Host cannot contain spaces';
    return null;
  }

  String? get portError => parsedPort == null ? 'Port must be 1–65535' : null;

  String? get usernameError =>
      username.trim().isEmpty ? 'Username is required' : null;

  /// The credential that will be persisted, or `null` if not ready.
  String? get secret => switch (authChoice) {
        AuthChoice.generateKey => generatedKey?.privateKeyPem,
        AuthChoice.importKey =>
          importedKeyPem.trim().isEmpty ? null : importedKeyPem.trim(),
        AuthChoice.password => password.isEmpty ? null : password,
      };

  bool get isValid =>
      hostError == null &&
      portError == null &&
      usernameError == null &&
      secret != null;

  ServerProfile toProfile(String id) => ServerProfile(
        id: id,
        label: label.trim().isEmpty ? host.trim() : label.trim(),
        host: host.trim(),
        port: parsedPort ?? 22,
        username: username.trim(),
        authMethod: authChoice.method,
      );
}

final keyServiceProvider = Provider<KeyService>((_) => const KeyService());

class AddServerFormNotifier extends Notifier<AddServerFormState> {
  @override
  AddServerFormState build() => const AddServerFormState();

  void setLabel(String v) => state = state.copyWith(label: v, clearError: true);
  void setHost(String v) => state = state.copyWith(host: v, clearError: true);
  void setPort(String v) => state = state.copyWith(port: v, clearError: true);
  void setUsername(String v) =>
      state = state.copyWith(username: v, clearError: true);
  void setImportedKey(String v) =>
      state = state.copyWith(importedKeyPem: v, clearError: true);
  void setPassword(String v) =>
      state = state.copyWith(password: v, clearError: true);

  void setAuthChoice(AuthChoice c) =>
      state = state.copyWith(authChoice: c, clearError: true);

  Future<void> generateKey() async {
    try {
      final key = await ref.read(keyServiceProvider).generateEd25519();
      state = state.copyWith(generatedKey: key, clearError: true);
    } on UnimplementedError catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  /// Validates the imported key without connecting anywhere.
  String? importedKeyError() {
    if (state.authChoice != AuthChoice.importKey) return null;
    return ref.read(keyServiceProvider).validatePrivateKeyPem(state.importedKeyPem);
  }

  void setSubmitting(bool v) => state = state.copyWith(submitting: v);
  void setError(String message) =>
      state = state.copyWith(error: message, submitting: false);
}

final addServerFormProvider = NotifierProvider.autoDispose<AddServerFormNotifier,
    AddServerFormState>(AddServerFormNotifier.new);
