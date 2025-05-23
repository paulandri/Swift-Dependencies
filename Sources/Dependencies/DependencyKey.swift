/// A key for accessing dependencies.
///
/// Types conform to this protocol to extend ``DependencyValues`` with custom dependencies. It is
/// similar to SwiftUI's `EnvironmentKey` protocol, which is used to add values to
/// `EnvironmentValues`.
///
/// `DependencyKey` has one main requirement, ``liveValue``, which must return a default value for
/// your dependency that is used when the application is run in a simulator or device. If the
/// ``liveValue`` is accessed while your feature runs in tests a test failure will be
/// triggered.
///
/// To add a `UserClient` dependency that can fetch and save user values can be done like so:
///
/// ```swift
/// // The user client dependency.
/// struct UserClient {
///   var fetchUser: (User.ID) async throws -> User
///   var saveUser: (User) async throws -> Void
/// }
/// // Conform to DependencyKey to provide a live implementation of
/// // the interface.
/// extension UserClient: DependencyKey {
///   static let liveValue = Self(
///     fetchUser: { /* Make request to fetch user */ },
///     saveUser: { /* Make request to save user */ }
///   )
/// }
/// // Register the dependency within DependencyValues.
/// extension DependencyValues {
///   var userClient: UserClient {
///     get { self[UserClient.self] }
///     set { self[UserClient.self] = newValue }
///   }
/// }
/// ```
///
/// When a dependency is first accessed its value is cached so that it will not be requested again.
/// This means if your `liveValue` is implemented as a computed property instead of a `static let`,
/// then it will only be called a single time:
///
/// ```swift
/// extension UserClient: DependencyKey {
///   static var liveValue: Self {
///     // Only called once when dependency is first accessed.
///     return Self(/* ... */)
///   }
/// }
/// ```
///
/// `DependencyKey` inherits from ``TestDependencyKey``, which has two other overridable
/// requirements: ``TestDependencyKey/testValue``, which should return a default value for the
/// purpose of testing, and ``TestDependencyKey/previewValue-8u2sy``, which can return a default
/// value suitable for Xcode previews. When left unimplemented, these endpoints will return the
/// ``liveValue``, instead.
///
/// If you plan on separating your interface from your live implementation, conform to
/// ``TestDependencyKey`` in your interface module, and conform to `DependencyKey` in your
/// implementation module.
///
/// See the <doc:LivePreviewTest> article for more information.
public protocol DependencyKey<Value>: TestDependencyKey {
  /// The live value for the dependency key.
  ///
  /// This is the value used by default when running the application in a simulator or on a device.
  /// Using a live dependency in a test context will lead to a test failure as you should mock your
  /// dependencies for tests.
  ///
  /// To automatically supply a test dependency in a test context, consider implementing the
  /// ``testValue-535kh`` requirement.
  static var liveValue: Value { get }

  // NB: The associated type and requirements of TestDependencyKey are repeated in this protocol
  //     due to a Swift compiler bug that prevents it from inferring the associated type in
  //     in the base protocol. See this issue for more information:
  //     https://github.com/apple/swift/issues/61077

  /// The associated type representing the type of the dependency key's value.
  associatedtype Value = Self

  /// The preview value for the dependency key.
  ///
  /// This value is automatically used when the associated dependency value is accessed from an
  /// Xcode preview, as well as when the current ``DependencyValues/context`` is set to
  /// ``DependencyContext/preview``:
  ///
  /// ```swift
  /// withDependencies {
  ///   $0.context = .preview
  /// } operation: {
  ///   // Dependencies accessed here default to their "preview" value
  /// }
  /// ```
  static var previewValue: Value { get }

  /// The test value for the dependency key.
  ///
  /// This value is automatically used when the associated dependency value is accessed from an
  /// XCTest run, as well as when the current ``DependencyValues/context`` is set to
  /// ``DependencyContext/test``:
  ///
  /// ```swift
  /// withDependencies {
  ///   $0.context = .test
  /// } operation: {
  ///   // Dependencies accessed here default to their "test" value
  /// }
  /// ```
  static var testValue: Value { get }
}

/// A key for accessing test dependencies.
///
/// This protocol lives one layer below ``DependencyKey`` and allows you to separate a dependency's
/// interface from its live implementation.
///
/// ``TestDependencyKey`` has one main requirement, ``testValue``, which must return a default value
/// for the purposes of testing, and one optional requirement, ``previewValue-8u2sy``, which can
/// return a default value suitable for Xcode previews, or the ``testValue``, if left unimplemented.
///
/// See ``DependencyKey`` to define a static, default value for the live application.
public protocol TestDependencyKey<Value> {
  /// The associated type representing the type of the dependency key's value.
  associatedtype Value: Sendable = Self

  /// The preview value for the dependency key.
  ///
  /// This value is automatically used when the associated dependency value is accessed from an
  /// Xcode preview, as well as when the current ``DependencyValues/context`` is set to
  /// ``DependencyContext/preview``:
  ///
  /// ```swift
  /// withDependencies {
  ///   $0.context = .preview
  /// } operation: {
  ///   // Dependencies accessed here default to their "preview" value
  /// }
  /// ```
  static var previewValue: Value { get }

  /// The test value for the dependency key.
  ///
  /// This value is automatically used when the associated dependency value is accessed from an
  /// XCTest run, as well as when the current ``DependencyValues/context`` is set to
  /// ``DependencyContext/test``:
  ///
  /// ```swift
  /// withDependencies {
  ///   $0.context = .test
  /// } operation: {
  ///   // Dependencies accessed here default to their "test" value
  /// }
  /// ```
  static var testValue: Value { get }
}

extension DependencyKey {
  /// A default implementation that provides the ``liveValue`` to Xcode previews.
  ///
  /// You may provide your own default `previewValue` in your conformance to ``TestDependencyKey``,
  /// which will take precedence over this implementation. If you are going to provide your own
  /// `previewValue` implementation, be sure to do it in the same module as the
  /// ``TestDependencyKey``.
  public static var previewValue: Value { Self.liveValue }

  /// A default implementation that provides the ``previewValue`` to test runs (or ``liveValue``,
  /// if no preview value is implemented), but will trigger a test failure when accessed.
  ///
  /// To prevent test failures, explicitly override the dependency in any tests in which it is
  /// accessed:
  ///
  /// ```swift
  /// @Test
  /// func featureThatUsesMyDependency() {
  ///   withDependencies {
  ///     $0.myDependency = .mock  // Override dependency
  ///   } operation: {
  ///     // Test feature with dependency overridden
  ///   }
  /// }
  /// ```
  ///
  /// You may provide your own default `testValue` in your conformance to ``TestDependencyKey``,
  /// which will take precedence over this implementation.
  public static var testValue: Value {
    #if DEBUG
      guard !DependencyValues.isSetting
      else { return Self.previewValue }

      var dependencyDescription = ""
      if let fileID = DependencyValues.currentDependency.fileID,
        let line = DependencyValues.currentDependency.line
      {
        dependencyDescription.append(
          """
            Location:
              \(fileID):\(line)

          """
        )
      }
      dependencyDescription.append(
        Self.self == Value.self
          ? """
            Dependency:
              \(typeName(Value.self))
          """
          : """
            Key:
              \(typeName(Self.self))
            Value:
              \(typeName(Value.self))
          """
      )

      let (argument, override) =
        DependencyValues.currentDependency.name
        .map {
          "\($0)" == "subscript(key:)"
            ? ("@Dependency(\(typeName(Self.self)).self)", "'\(typeName(Self.self)).self'")
            : ("@Dependency(\\.\($0))", "'\($0)'")
        }
        ?? ("A dependency", "the dependency")

      reportIssue(
        """
        \(argument) has no test implementation, but was accessed from a test context:

        \(dependencyDescription)

        Dependencies registered with the library are not allowed to use their default, live \
        implementations when run from tests.

        To fix, override \(override) with a test value. If you are using the \
        Composable Architecture, mutate the 'dependencies' property on your 'TestStore'. \
        Otherwise, use 'withDependencies' to define a scope for the override. If you'd like to \
        provide a default value for all tests, implement the 'testValue' requirement of the \
        'DependencyKey' protocol.
        """
      )
    #endif
    return Self.previewValue
  }
}

extension TestDependencyKey {
  /// A default implementation that provides the
  /// <doc:/documentation/Dependencies/TestDependencyKey/testValue> to Xcode previews.
  ///
  /// You may provide your own default `previewValue` in your conformance to ``TestDependencyKey``,
  /// which will take precedence over this implementation.
  public static var previewValue: Value { Self.testValue }
}

extension TestDependencyKey {
  /// Determines if it is appropriate to report an issue in an accessed `testValue`.
  ///
  /// When implementing the `testValue` requirement of ``TestDependencyKey`` you may want to report
  /// an issue so that the user of the dependency is forced to override it in tests. However, one
  /// cannot unconditionally report an issue because the getter of `testValue` is invoked when
  /// setting.
  ///
  /// Check this value in order to determine if it is appropriate to report an issue or not:
  ///
  /// ```swift
  /// private enum DefaultDatabaseKey: DependencyKey {
  ///   static var testValue: any DatabaseWriter {
  ///     if shouldReportUnimplemented {
  ///       reportIssue("A blank, in-memory database is being used.")
  ///     }
  ///     return InMemoryDatabase()
  ///   }
  /// }
  /// ```
  public static var shouldReportUnimplemented: Bool {
    #if DEBUG
      return !DependencyValues.isSetting
    #else
      return false
    #endif
  }
}
