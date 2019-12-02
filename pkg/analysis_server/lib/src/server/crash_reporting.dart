// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/exception/exception.dart';
import 'package:analyzer/instrumentation/noop_service.dart';
import 'package:analyzer/instrumentation/plugin_data.dart';
import 'package:telemetry/crash_reporting.dart';

class CrashReportingInstrumentation extends NoopInstrumentationService {
  final CrashReportSender reporter;

  CrashReportingInstrumentation(this.reporter);

  @override
  void logException(dynamic exception, [StackTrace stackTrace]) {
    if (exception is CaughtException) {
      // Get the root CaughtException, which matters most for debugging.
      exception = exception.rootCaughtException;
      // Report the root exception stack trace.
      stackTrace = exception.stackTrace;
      // Report the dynamic exception object that the CaughtException holds.
      exception = exception.exception;
    }
    reporter
        .sendReport(exception, stackTrace: stackTrace ?? StackTrace.current)
        .catchError((error) {
      // We silently ignore errors sending crash reports (network issues, ...).
    });
  }

  @override
  void logPluginException(
      PluginData plugin, dynamic exception, StackTrace stackTrace) {
    // TODO(mfairhurst): send plugin information too.
    reporter.sendReport(exception, stackTrace: stackTrace).catchError((error) {
      // We silently ignore errors sending crash reports (network issues, ...).
    });
  }
}
