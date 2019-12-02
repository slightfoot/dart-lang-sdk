// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analysis_server/protocol/protocol.dart';
import 'package:analysis_server/protocol/protocol_constants.dart';
import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:analysis_server/src/analysis_server.dart';
import 'package:analysis_server/src/server/error_notifier.dart';
import 'package:analysis_server/src/socket_server.dart';
import 'package:analysis_server/src/utilities/mocks.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:test/test.dart';

main() {
  group('SocketServer', () {
    test('createAnalysisServer_successful',
        SocketServerTest.createAnalysisServer_successful);
    test('createAnalysisServer_alreadyStarted',
        SocketServerTest.createAnalysisServer_alreadyStarted);
    test('requestHandler_exception', SocketServerTest.requestHandler_exception);
    test('requestHandler_futureException',
        SocketServerTest.requestHandler_futureException);
  });
}

class SocketServerTest {
  static void createAnalysisServer_alreadyStarted() {
    MockServerChannel channel1 = new MockServerChannel();
    MockServerChannel channel2 = new MockServerChannel();
    SocketServer server = _createSocketServer(channel1);
    expect(
        channel1.notificationsReceived[0].event, SERVER_NOTIFICATION_CONNECTED);
    server.createAnalysisServer(channel2);
    channel1.expectMsgCount(notificationCount: 1);
    channel2.expectMsgCount(responseCount: 1);
    expect(channel2.responsesReceived[0].id, equals(''));
    expect(channel2.responsesReceived[0].error, isNotNull);
    expect(channel2.responsesReceived[0].error.code,
        equals(RequestErrorCode.SERVER_ALREADY_STARTED));
    channel2
        .sendRequest(new ServerShutdownParams().toRequest('0'))
        .then((Response response) {
      expect(response.id, equals('0'));
      expect(response.error, isNotNull);
      expect(
          response.error.code, equals(RequestErrorCode.SERVER_ALREADY_STARTED));
      channel2.expectMsgCount(responseCount: 2);
    });
  }

  static Future createAnalysisServer_successful() {
    MockServerChannel channel = new MockServerChannel();
    _createSocketServer(channel);
    channel.expectMsgCount(notificationCount: 1);
    expect(
        channel.notificationsReceived[0].event, SERVER_NOTIFICATION_CONNECTED);
    return channel
        .sendRequest(new ServerShutdownParams().toRequest('0'))
        .then((Response response) {
      expect(response.id, equals('0'));
      expect(response.error, isNull);
      channel.expectMsgCount(responseCount: 1, notificationCount: 1);
    });
  }

  static Future requestHandler_exception() {
    MockServerChannel channel = new MockServerChannel();
    SocketServer server = _createSocketServer(channel);
    channel.expectMsgCount(notificationCount: 1);
    expect(
        channel.notificationsReceived[0].event, SERVER_NOTIFICATION_CONNECTED);
    _MockRequestHandler handler = new _MockRequestHandler(false);
    server.analysisServer.handlers = [handler];
    var request = new ServerGetVersionParams().toRequest('0');
    return channel.sendRequest(request).then((Response response) {
      expect(response.id, equals('0'));
      expect(response.error, isNotNull);
      expect(response.error.code, equals(RequestErrorCode.SERVER_ERROR));
      expect(response.error.message, equals('mock request exception'));
      expect(response.error.stackTrace, isNotNull);
      expect(response.error.stackTrace, isNotEmpty);
      channel.expectMsgCount(responseCount: 1, notificationCount: 1);
    });
  }

  static Future requestHandler_futureException() async {
    MockServerChannel channel = new MockServerChannel();
    SocketServer server = _createSocketServer(channel);
    _MockRequestHandler handler = new _MockRequestHandler(true);
    server.analysisServer.handlers = [handler];
    var request = new ServerGetVersionParams().toRequest('0');
    Response response = await channel.sendRequest(request, throwOnError: false);
    expect(response.id, equals('0'));
    expect(response.error, isNull);
    channel.expectMsgCount(responseCount: 1, notificationCount: 2);
    expect(channel.notificationsReceived[1].event, SERVER_NOTIFICATION_ERROR);
  }

  static SocketServer _createSocketServer(MockServerChannel channel) {
    final errorNotifier = new ErrorNotifier();
    final server = new SocketServer(
        new AnalysisServerOptions(),
        new DartSdkManager('', false),
        errorNotifier,
        null,
        null,
        null,
        null,
        null);

    server.createAnalysisServer(channel);
    errorNotifier.server = server.analysisServer;
    AnalysisEngine.instance.instrumentationService = errorNotifier;

    return server;
  }
}

class _MockRequestHandler implements RequestHandler {
  final bool futureException;

  _MockRequestHandler(this.futureException);

  @override
  Response handleRequest(Request request) {
    if (futureException) {
      new Future(throwException);
      return new Response(request.id);
    }
    throw 'mock request exception';
  }

  void throwException() {
    throw 'mock future exception';
  }
}
