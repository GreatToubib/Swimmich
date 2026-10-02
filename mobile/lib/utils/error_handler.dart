import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
// ignore: depend_on_referenced_packages
import 'package:stack_trace/stack_trace.dart';

// Swimmich: also keep the error in the app's own log (Settings > Logs), so a
// failure in a release build can be read back; upstream only prints it in debug.
final _log = Logger('ErrorHandler');

void handleError(Object error, {StackTrace? stack, String? description}) {
  _log.severe(description ?? 'Unhandled error', error, stack);

  String? stackTrace;
  if (stack != null) {
    final trace = Trace.from(stack);
    final clean = trace.foldFrames(
      (frame) => frame.package == 'flutter' || frame.package == 'flutter_test' || frame.isCore,
      terse: true,
    );
    stackTrace = clean.toString();
  }

  dPrint(
    () => 'Error${description != null ? ' ($description)' : ''}: $error${stackTrace != null ? '\n$stackTrace' : ''}',
  );

  final String message;
  if (serverErrorMessage(error) case final String serverMessage) {
    message = serverMessage;
  } else if (isConnectionError(error)) {
    message = StaticTranslations.instance.login_form_server_error;
  } else {
    message = StaticTranslations.instance.scaffold_body_error_occurred;
  }

  snackbar.error(message);
}

@visibleForTesting
String? serverErrorMessage(Object error) {
  if (error is! ApiException || error.innerException != null || error.message == null) {
    return null;
  }

  try {
    final body = jsonDecode(error.message!);
    if (body is Map && body['message'] != null) {
      final message = body['message'];
      return message is List ? message.join(', ') : message.toString();
    }
  } catch (_) {
    // The body was not JSON; fall back to the raw payload below.
  }
  return error.message;
}

@visibleForTesting
bool isConnectionError(Object error) => error is ApiException && error.innerException != null;
