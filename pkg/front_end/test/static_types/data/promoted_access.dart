// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*cfe.library: nnbd=false*/
/*cfe:nnbd.library: nnbd=true*/

class Class<T> {
  method(T o) {
    if (/*cfe|dart2js.T*/ /*cfe:nnbd.T%*/ o is Class) {
      /*cfe|dart2js.T & Class<dynamic>*/
      /*cfe:nnbd.T! & Class<dynamic>!*/
      o. /*invoke: dynamic*/ method(/*Null*/ null);
    }
  }
}

method<T>(T o) {
  if (/*cfe|dart2js.T*/ /*cfe:nnbd.T%*/ o is Class) {
    /*cfe|dart2js.T & Class<dynamic>*/
    /*cfe:nnbd.T! & Class<dynamic>!*/
    o. /*invoke: dynamic*/ method(/*Null*/ null);
  }
}

main() {
  var c = new
      /*cfe|dart2js.Class<dynamic>*/
      /*cfe:nnbd.Class<dynamic>!*/
      Class/*<dynamic>*/();
  /*cfe|dart2js.Class<dynamic>*/ /*cfe:nnbd.Class<dynamic>!*/ c
      . /*invoke: dynamic*/ method(
          /*cfe|dart2js.Class<dynamic>*/ /*cfe:nnbd.Class<dynamic>!*/ c);
  /*invoke: dynamic*/ method
      /*cfe|dart2js.<Class<dynamic>>*/ /*cfe:nnbd.<Class<dynamic>!>*/ (
          /*cfe|dart2js.Class<dynamic>*/ /*cfe:nnbd.Class<dynamic>!*/ c);
}
