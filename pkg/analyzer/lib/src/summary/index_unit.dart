// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/generated/utilities_dart.dart';
import 'package:analyzer/src/summary/format.dart';
import 'package:analyzer/src/summary/idl.dart';

/**
 * Object that gathers information about the whole package index and then uses
 * it to assemble a new [PackageIndexBuilder].  Call [index] on each compilation
 * unit to be indexed, then call [assemble] to retrieve the complete index for
 * the package.
 */
class PackageIndexAssembler {
  /**
   * Map associating referenced elements with their [_ElementInfo]s.
   */
  final Map<Element, _ElementInfo> _elementMap = <Element, _ElementInfo>{};

  /**
   * Map associating [CompilationUnitElement]s with their identifiers, which
   * are indices into [_elementLibraryUris] and [_elementUnitUris].
   */
  final Map<CompilationUnitElement, int> _elementUnitMap =
      <CompilationUnitElement, int>{};

  /**
   * Each item of this list corresponds to the library URI of a unique
   * [CompilationUnitElement].  It is an index into [_uris].
   */
  final List<int> _elementLibraryUris = <int>[];

  /**
   * Each item of this list corresponds to the unit URI of a unique
   * [CompilationUnitElement].  It is an index into [_uris].
   */
  final List<int> _elementUnitUris = <int>[];

  /**
   * Map associating URIs with their identifiers, which are indices
   * into [_uris].
   */
  final Map<String, int> _uriMap = <String, int>{};

  /**
   * List of unique URIs used in this index.
   */
  final List<String> _uris = <String>[];

  /**
   * List of information about each unit indexed in this index.
   */
  final List<_UnitIndexAssembler> _units = <_UnitIndexAssembler>[];

  /**
   * Assemble a new [PackageIndexBuilder] using the information gathered by
   * [index].
   */
  PackageIndexBuilder assemble() {
    List<_ElementInfo> elementInfoList = _elementMap.values.toList();
    elementInfoList.sort((a, b) {
      return a.offset - b.offset;
    });
    for (int i = 0; i < elementInfoList.length; i++) {
      elementInfoList[i].id = i;
    }
    return new PackageIndexBuilder(
        elementLibraryUris: _elementLibraryUris,
        elementUnitUris: _elementUnitUris,
        elementUnits: elementInfoList.map((e) => e.unitId).toList(),
        elementOffsets: elementInfoList.map((e) => e.offset).toList(),
        uris: _uris,
        units: _units.map((unit) => unit.assemble()).toList());
  }

  /**
   * Index the given fully resolved [unit].
   */
  void index(CompilationUnit unit) {
    CompilationUnitElement unitElement = unit.element;
    _UnitIndexAssembler assembler = new _UnitIndexAssembler(this, unitElement);
    _units.add(assembler);
    unit.accept(new _IndexContributor(assembler));
  }

  /**
   * Return the unique [_ElementInfo] corresponding the [element].  The field
   * [_ElementInfo.id] is filled by [assemble] during final sorting.
   */
  _ElementInfo _getElementInfo(Element element) {
    return _elementMap.putIfAbsent(element, () {
      CompilationUnitElement unitElement = getUnitElement(element);
      int unitId = _getUnitElementId(unitElement);
      return new _ElementInfo(unitId, element.nameOffset);
    });
  }

  /**
   * Add information about [unitElement] to [_elementUnitUris] and
   * [_elementLibraryUris] if necessary, and return the location in those
   * arrays representing [unitElement].
   */
  int _getUnitElementId(CompilationUnitElement unitElement) {
    return _elementUnitMap.putIfAbsent(unitElement, () {
      assert(_elementLibraryUris.length == _elementUnitUris.length);
      int id = _elementUnitUris.length;
      _elementLibraryUris.add(_getUriId(unitElement.library.source.uri));
      _elementUnitUris.add(_getUriId(unitElement.source.uri));
      return id;
    });
  }

  /**
   * Add information about [uri] to [_uris] if necessary, and return the
   * location in this array representing [uri].
   */
  int _getUriId(Uri uri) {
    String str = uri.toString();
    return _uriMap.putIfAbsent(str, () {
      int id = _uris.length;
      _uris.add(str);
      return id;
    });
  }

  /**
   * Return the [CompilationUnitElement] that should be used for [element].
   * Throw [StateError] if the [element] is not linked into a unit.
   */
  static CompilationUnitElement getUnitElement(Element element) {
    for (Element e = element; e != null; e = e.enclosingElement) {
      if (e is CompilationUnitElement) {
        return e;
      }
      if (e is LibraryElement) {
        return e.definingCompilationUnit;
      }
    }
    throw new StateError(element.toString());
  }
}

/**
 * Information about an element referenced in index.
 */
class _ElementInfo {
  /**
   * The identifier of the [CompilationUnitElement] containing this element.
   */
  final int unitId;

  /**
   * The name offset of the element.
   */
  final int offset;

  /**
   * The unique id of the element.  It is set after indexing of the whole
   * package is done and we are assembling the full package index.
   */
  int id;

  _ElementInfo(this.unitId, this.offset);
}

/**
 * Visits a resolved AST and adds relationships into [_UnitIndexAssembler].
 */
class _IndexContributor extends GeneralizingAstVisitor {
  final _UnitIndexAssembler assembler;

  _IndexContributor(this.assembler);

  /**
   * Record information about a [ClassDeclaration] or [ClassTypeAlias] with
   * the given [nameNode].  Nodes [superNode], [withClause] and
   * [implementsClause] can be `null`.
   */
  void recordClassClauses(SimpleIdentifier nameNode, TypeName superNode,
      WithClause withClause, ImplementsClause implementsClause) {
    if (superNode != null) {
      recordSuperType(superNode, IndexRelationKind.IS_EXTENDED_BY);
    } else {
      ClassElement element = nameNode.staticElement;
      InterfaceType superType = element.supertype;
      if (superType != null) {
        ClassElement objectElement = superType.element;
        recordRelationOffset(objectElement, IndexRelationKind.IS_EXTENDED_BY,
            nameNode.offset, 0);
      }
    }
    if (withClause != null) {
      for (TypeName mixinNode in withClause.mixinTypes) {
        recordSuperType(mixinNode, IndexRelationKind.IS_MIXED_IN_BY);
      }
    }
    if (implementsClause != null) {
      for (TypeName interfaceNode in implementsClause.interfaces) {
        recordSuperType(interfaceNode, IndexRelationKind.IS_IMPLEMENTED_BY);
      }
    }
  }

  /**
   * Records reference to defining [CompilationUnitElement] of the given
   * [LibraryElement].
   */
  void recordLibraryReference(UriBasedDirective node, LibraryElement library) {
    recordRelation(library, IndexRelationKind.IS_REFERENCED_BY, node?.uri);
  }

  /**
   * Record reference to the given operator [Element] and name.
   */
  void recordOperatorReference(Token operator, Element element) {
    recordRelationToken(element, IndexRelationKind.IS_INVOKED_BY, operator);
    // TODO(scheglov) do we need this?
//    // prepare location
//    LocationImpl location = _createLocationForToken(operator, element != null);
//    // record name reference
//    {
//      String name = operator.lexeme;
//      if (name == "++") {
//        name = "+";
//      }
//      if (name == "--") {
//        name = "-";
//      }
//      if (StringUtilities.endsWithChar(name, 0x3D) && name != "==") {
//        name = name.substring(0, name.length - 1);
//      }
//      IndexableName indexableName = new IndexableName(name);
//      recordRelationshipIndexable(
//          indexableName, IndexConstants.IS_INVOKED_BY, location);
//    }
//    // record element reference
//    if (element != null) {
//      recordRelationshipElement(
//          element, IndexConstants.IS_INVOKED_BY, location);
//    }
  }

  /**
   * Record that [element] has a relation of the given [kind] at the location
   * of the given [node].
   */
  void recordRelation(Element element, IndexRelationKind kind, AstNode node) {
    if (element != null && node != null) {
      recordRelationOffset(element, kind, node.offset, node.length);
    }
  }

  /**
   * Record that [element] has a relation of the given [kind] at the given
   * [offset] and [length].
   */
  void recordRelationOffset(
      Element element, IndexRelationKind kind, int offset, int length) {
    // Ignore elements that can't be referenced outside of the unit.
    if (element == null ||
        element is LocalVariableElement ||
        element is ParameterElement &&
            element.parameterKind != ParameterKind.NAMED ||
        element is FunctionElement &&
            element.enclosingElement is ExecutableElement) {
      return;
    }
    // Add the relation.
    assembler.addRelation(element, kind, offset, length);
  }

  /**
   * Record that [element] has a relation of the given [kind] at the location
   * of the given [token].
   */
  void recordRelationToken(
      Element element, IndexRelationKind kind, Token token) {
    if (element != null && token != null) {
      recordRelationOffset(element, kind, token.offset, token.length);
    }
  }

  /**
   * Records a relation between [superNode] and its [Element].
   */
  void recordSuperType(TypeName superNode, IndexRelationKind kind) {
    if (superNode != null) {
      Identifier superName = superNode.name;
      if (superName != null) {
        Element superElement = superName.staticElement;
        recordRelation(superElement, kind, superName);
      }
    }
  }

  /**
   * Record the top-level [element] definition.
   */
  void recordTopLevelElementDefinition(Element element) {
    // TODO(scheglov) do we need this?
//    if (element?.enclosingElement is CompilationUnitElement) {
//      IndexableElement indexable = new IndexableElement(element);
//      int offset = element.nameOffset;
//      int length = element.nameLength;
//      LocationImpl location = new LocationImpl(indexable, offset, length);
//      recordRelationshipElement(
//          _libraryElement, IndexConstants.DEFINES, location);
//      _store.recordTopLevelDeclaration(element);
//    }
  }

  void recordUriFileReference(UriBasedDirective directive) {
    Element element = directive.element;
    recordRelation(element, IndexRelationKind.IS_REFERENCED_BY, directive.uri);
  }

  @override
  visitAssignmentExpression(AssignmentExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    super.visitAssignmentExpression(node);
  }

  @override
  visitBinaryExpression(BinaryExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    super.visitBinaryExpression(node);
  }

  @override
  visitClassDeclaration(ClassDeclaration node) {
    ClassElement element = node.element;
    recordTopLevelElementDefinition(element);
    recordClassClauses(node.name, node.extendsClause?.superclass,
        node.withClause, node.implementsClause);
    super.visitClassDeclaration(node);
  }

  @override
  visitClassTypeAlias(ClassTypeAlias node) {
    ClassElement element = node.element;
    recordTopLevelElementDefinition(element);
    recordClassClauses(
        node.name, node.superclass, node.withClause, node.implementsClause);
    super.visitClassTypeAlias(node);
  }

  @override
  visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    SimpleIdentifier fieldName = node.fieldName;
    if (fieldName != null) {
      Element element = fieldName.staticElement;
      recordRelation(element, IndexRelationKind.IS_REFERENCED_BY, fieldName);
    }
    node.expression?.accept(this);
  }

  @override
  visitConstructorName(ConstructorName node) {
    ConstructorElement element = node.staticElement;
    // in 'class B = A;' actually A constructors are invoked
    // TODO(scheglov) add support for multiple levels of redirection
    // TODO(scheglov) test for a loop of redirection
    if (element != null &&
        element.isSynthetic &&
        element.redirectedConstructor != null) {
      element = element.redirectedConstructor;
    }
    // record relation
    if (node.name != null) {
      int offset = node.period.offset;
      int length = node.name.end - offset;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, length);
    } else {
      int offset = node.type.end;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, 0);
    }
    super.visitConstructorName(node);
  }

  @override
  visitEnumDeclaration(EnumDeclaration node) {
    ClassElement element = node.element;
    recordTopLevelElementDefinition(element);
    super.visitEnumDeclaration(node);
  }

  @override
  visitExportDirective(ExportDirective node) {
    ExportElement element = node.element;
    if (element != null) {
      LibraryElement expLibrary = element.exportedLibrary;
      recordLibraryReference(node, expLibrary);
    }
    recordUriFileReference(node);
    super.visitExportDirective(node);
  }

  @override
  visitFunctionDeclaration(FunctionDeclaration node) {
    Element element = node.element;
    recordTopLevelElementDefinition(element);
    super.visitFunctionDeclaration(node);
  }

  @override
  visitFunctionTypeAlias(FunctionTypeAlias node) {
    Element element = node.element;
    recordTopLevelElementDefinition(element);
    super.visitFunctionTypeAlias(node);
  }

  @override
  visitImportDirective(ImportDirective node) {
    ImportElement element = node.element;
    if (element != null) {
      LibraryElement impLibrary = element.importedLibrary;
      recordLibraryReference(node, impLibrary);
    }
    recordUriFileReference(node);
    super.visitImportDirective(node);
  }

  @override
  visitIndexExpression(IndexExpression node) {
    MethodElement element = node.bestElement;
    if (element is MethodElement) {
      Token operator = node.leftBracket;
      recordRelationToken(element, IndexRelationKind.IS_INVOKED_BY, operator);
    }
    super.visitIndexExpression(node);
  }

  @override
  visitMethodInvocation(MethodInvocation node) {
    SimpleIdentifier name = node.methodName;
    // TODO(scheglov) do we need this?
//    LocationImpl location = _createLocationForNode(name);
//    // name invocation
//    recordRelationshipIndexable(
//        new IndexableName(name.name), IndexConstants.IS_INVOKED_BY, location);
    // element invocation
    Element element = name.bestElement;
    if (element is MethodElement ||
        element is PropertyAccessorElement ||
        element is FunctionElement ||
        element is VariableElement) {
      recordRelation(element, IndexRelationKind.IS_INVOKED_BY, node);
    } else if (element is ClassElement) {
      recordRelation(element, IndexRelationKind.IS_REFERENCED_BY, node);
    }
    node.target?.accept(this);
    node.argumentList?.accept(this);
  }

  @override
  visitPartDirective(PartDirective node) {
    recordRelation(node.element, IndexRelationKind.IS_REFERENCED_BY, node);
    recordUriFileReference(node);
    super.visitPartDirective(node);
  }

  @override
  visitPartOfDirective(PartOfDirective node) {
    recordRelation(node.element, IndexRelationKind.IS_REFERENCED_BY, node);
  }

  @override
  visitPostfixExpression(PostfixExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    super.visitPostfixExpression(node);
  }

  @override
  visitPrefixExpression(PrefixExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    super.visitPrefixExpression(node);
  }

  @override
  visitRedirectingConstructorInvocation(RedirectingConstructorInvocation node) {
    ConstructorElement element = node.staticElement;
    if (node.constructorName != null) {
      int offset = node.period.offset;
      int length = node.constructorName.end - offset;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, length);
    } else {
      int offset = node.thisKeyword.end;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, 0);
    }
    super.visitRedirectingConstructorInvocation(node);
  }

  @override
  visitSimpleIdentifier(SimpleIdentifier node) {
    // TODO(scheglov) do we need this?
//    IndexableName indexableName = new IndexableName(node.name);
//    LocationImpl location = _createLocationForNode(node);
//    if (location == null) {
//      return;
//    }
    // name in declaration
    if (node.inDeclarationContext()) {
      // TODO(scheglov) do we need this?
//      recordRelationshipIndexable(
//          indexableName, IndexConstants.NAME_IS_DEFINED_BY, location);
      return;
    }
    // name in an extends/with/implements clause
    if (_isInExtendsWithImplementsClause(node)) {
      return;
    }
    Element element = node.bestElement;
    // this.field parameter
    if (element is FieldFormalParameterElement) {
      recordRelation(element.field, IndexRelationKind.IS_REFERENCED_BY, node);
      return;
    }
    // record specific relations
    // TODO(scheglov) consider removing the conditions
    if (element is ClassElement ||
        element is FunctionElement ||
        element is FunctionTypeAliasElement ||
        element is LabelElement ||
        element is MethodElement ||
        element is PrefixElement ||
        element is PropertyAccessorElement ||
        element is PropertyInducingElement ||
        element is TypeParameterElement) {
      recordRelation(element, IndexRelationKind.IS_REFERENCED_BY, node);
    }
  }

  @override
  visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    ConstructorElement element = node.staticElement;
    if (node.constructorName != null) {
      int offset = node.period.offset;
      int length = node.constructorName.end - offset;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, length);
    } else {
      int offset = node.superKeyword.end;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, 0);
    }
    super.visitSuperConstructorInvocation(node);
  }

  @override
  visitVariableDeclaration(VariableDeclaration node) {
    VariableElement element = node.element;
    recordTopLevelElementDefinition(element);
    // TODO(scheglov) do we need this?
//    // record declaration
//    {
//      SimpleIdentifier name = node.name;
//      LocationImpl location = _createLocationForNode(name);
//      location = _getLocationWithExpressionType(location, node.initializer);
//      recordRelationshipElement(
//          element, IndexConstants.NAME_IS_DEFINED_BY, location);
//    }
    super.visitVariableDeclaration(node);
  }

  static bool _isInExtendsWithImplementsClause(SimpleIdentifier node) {
    TypeName typeName;
    AstNode parent = node?.parent;
    AstNode parent2 = parent?.parent;
    if (parent is TypeName && parent.name == node) {
      typeName = parent;
    } else if (parent is PrefixedIdentifier &&
        parent.identifier == node &&
        parent2 is TypeName &&
        parent2.name == node) {
      typeName = parent2;
    } else {
      return false;
    }
    AstNode clause = typeName.parent;
    return clause is ExtendsClause ||
        clause is WithClause ||
        clause is ImplementsClause;
  }
}

/**
 * Information about a single relation.  Any [_RelationInfo] is always part
 * of a [_UnitIndexAssembler], so [offset] and [length] should be understood
 * within the context of the compilation unit pointed to by the
 * [_UnitIndexAssembler].
 */
class _RelationInfo {
  final _ElementInfo elementInfo;
  final IndexRelationKind kind;
  final int offset;
  final int length;

  _RelationInfo(this.elementInfo, this.kind, this.offset, this.length);
}

/**
 * Assembler of a single [CompilationUnit] index.  The intended usage sequence:
 *
 *  - Call [addRelation] for each relation found in the compilation unit.
 *  - Assign ids to all the [_ElementInfo] objects reachable from [relations].
 *  - Call [assemble] to produce the final unit index.
 */
class _UnitIndexAssembler {
  final PackageIndexAssembler pkg;
  final CompilationUnitElement unitElement;
  final List<_RelationInfo> relations = <_RelationInfo>[];

  _UnitIndexAssembler(this.pkg, this.unitElement);

  void addRelation(
      Element element, IndexRelationKind kind, int offset, int length) {
    try {
      _ElementInfo elementInfo = pkg._getElementInfo(element);
      relations.add(new _RelationInfo(elementInfo, kind, offset, length));
    } on StateError {}
  }

  /**
   * Assemble a new [UnitIndexBuilder] using the information gathered
   * by [addRelation]
   */
  UnitIndexBuilder assemble() {
    relations.sort((a, b) {
      return a.elementInfo.id - b.elementInfo.id;
    });
    return new UnitIndexBuilder(
        elements: relations.map((r) => r.elementInfo.id).toList(),
        kinds: relations.map((r) => r.kind).toList(),
        locationOffsets: relations.map((r) => r.offset).toList(),
        locationLengths: relations.map((r) => r.length).toList(),
        libraryUri: pkg._getUriId(unitElement.library.source.uri),
        unitUri: pkg._getUriId(unitElement.source.uri));
  }
}
