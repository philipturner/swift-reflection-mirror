import XCTest
@_spi(Reflection) import ReflectionMirror

struct ASimpleKPI {
  var w = 1
}

struct AMixedKPI {
  var string = "foo"
}

struct ANestedKPI {
  var simple = ASimpleKPI()
  var mixed = AMixedKPI()
}

final class AAATests: XCTestCase {
  func testMyCrasher() {
    var x = ANestedKPI()
    
    do {
      var result: [PartialKeyPath<ANestedKPI>] = []
      
      var out = [PartialKeyPath<ANestedKPI>]()
      _forEachFieldWithKeyPath(of: ANestedKPI.self, options: .ignoreUnknown) { _, kp in
        out.append(kp)
        return true
      }
      
      for kp in out {
        result.append(kp)
        if x[keyPath: kp] is ASimpleKPI {
          _forEachFieldWithKeyPath(of: ASimpleKPI.self, options: .ignoreUnknown) { _, nkp in
            result.append(kp.appending(path: nkp as AnyKeyPath)!)
            return true
          }
        } else if x[keyPath: kp] is AMixedKPI {
          var out2 = [AnyKeyPath]()
          _forEachFieldWithKeyPath(of: AMixedKPI.self, options: .ignoreUnknown) { _, nkp in
            out2.append(nkp as AnyKeyPath)
            return true
          }
          
          for nkp in out2 {
            result.append(kp.appending(path: nkp)!)
          }
        }
      }
    }
    
    do {
      var result: [PartialKeyPath<ANestedKPI>] = []
      
      var out = [PartialKeyPath<ANestedKPI>]()
      _forEachFieldWithKeyPath(of: ANestedKPI.self, options: .ignoreUnknown) { _, kp in
        out.append(kp)
        return true
      }
      
      for kp in out {
        result.append(kp)
        if x[keyPath: kp] is ASimpleKPI {
          _forEachFieldWithKeyPath(of: ASimpleKPI.self, options: .ignoreUnknown) { _, nkp in
            result.append(kp.appending(path: nkp as AnyKeyPath)!)
            return true
          }
        } else if x[keyPath: kp] is AMixedKPI {
          _forEachFieldWithKeyPath(of: AMixedKPI.self, options: .ignoreUnknown) { _, nkp in
            result.append(kp.appending(path: nkp as AnyKeyPath)!)
            return true
          }
        }
      }
    }
  }
}
