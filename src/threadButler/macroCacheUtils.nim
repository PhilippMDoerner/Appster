import std/[macros, macrocache, strformat, options]
import ./utils

const types = CacheTable"typeTable"
## Stores a list of types for a given "threadServer" based on a given name
## The procs are stored in a StatementList-NimNode for later retrieval,
## turning this effectively in a complicated Version of CacheTable[string, CacheSeq]

const routes = CacheTable"routeTable" ##
## Stores a list of procs for a given "threadServer" based on a given name
## The procs are stored in a StatementList-NimNode for later retrieval,
## turning this effectively in a complicated Version of CacheTable[string, CacheSeq]

type ThreadName* = distinct string
proc `==`*(x, y: ThreadName): bool {.borrow.}

proc typeName*(node: NimNode): string =
  ## Extracts the name of a type from an nnkTypeDef NimNode
  node.assertKind(nnkTypeDef)
  return $node[0]

proc firstParamType*(node: NimNode): NimNode =
  ## Extracts the nnkTypeDef NimNode of the first parameter from 
  ## an nnkProcDef NimNode
  node.assertKind(nnkProcDef)
  let firstParam = node.params[1]
  let typeNode = firstParam[1]
  case typeNode.kind:
    of nnkTypeDef: 
      return typeNode
    of nnkSym: 
      let typeDef = typeNode.getImpl() 
      typeDef.assertKind(nnkTypeDef)
      return typeDef
    else: error("This type of message type is not supported")

proc getRoutes*(name: ThreadName): seq[NimNode] =
  ## Returns a list of all registered routes for `name`
  ## Returns an empty list if no routes were ever registered for `name`.
  let name = name.string
  let hasRoutes = routes.hasKey(name)
  if not hasRoutes:
    return @[]
  
  for route in routes[name]:
    result.add(route)

proc getTypes*(name: ThreadName): seq[NimNode] =
  ## Returns a list of all registered types for `name`
  ## Returns an empty list if no types were ever registered for `name`.
  let name = name.string
  let hasTypes = types.hasKey(name)
  if not hasTypes:
    return @[]
  
  for typ in types[name]:
    result.add(typ)

proc hasTypeOfName*(name: ThreadName, typName: string): bool =
  ## Checks if a type of name `typName` is already registered for `name`.
  for typ in name.getTypes():
    if typ.typeName() == typName:
      return true
  
  return false

proc getTypeOfName*(name: ThreadName, typName: string): Option[NimNode] =
  ## Fetches the nnkTypeDef NimNode of a type with the name `typName` registered for `name`.
  for typ in name.getTypes():
    if typ.typeName() == typName:
      return some(typ)
  
  return none(NimNode)

proc validateType(name: ThreadName, typeDef: NimNode) =
  let typeName = typeDef.typeName()
  let isAlreadyRegistered = name.hasTypeOfName(typeName)
  if isAlreadyRegistered:
    let otherType = name.getTypeOfName(typeName)
    let addInfo = if otherType.isSome():
        fmt"(see: {otherType.get().lineInfo})"
      else:
        "(but could not find the type)"
    error(fmt"Failed to register '{typeName}' from '{typeDef.lineInfo}'. A type with that name was already registered {addInfo}")
  
proc addType*(name: ThreadName, typeDef: NimNode) =
  ## Stores the nnkTypeDef NimNode `typeDef` for `name` in the CacheTable `types`.
  ## Raises a compile-time error if a type with the same name was already registered for `name`.
  typeDef.assertKind(nnkTypeDef, "You need a type definition to store a type")
  let isFirstType = not types.hasKey(name.string)
  if isFirstType:
    types[name.string] = newStmtList()
  
  validateType(name, typeDef)
  
  types[name.string].add(typeDef)

proc hasProcForType*(name: ThreadName, typName: string): bool =
  ## Checks if a handler proc whose first parameter type is `typName`
  ## is already registered for `name`.
  for handlerProc in name.getRoutes():
    if handlerProc.firstParamType().typeName() == typName:
      return true
  
  return false

proc getProcForType*(name: ThreadName, typName: string): Option[NimNode] =
  ## Fetches the nnkProcDef NimNode of a handler proc whose first parameter type
  ## name is `typName` registered for `name`.
  for handlerProc in name.getRoutes():
    if handlerProc.firstParamType().typeName() == typName:
      return some(handlerProc)
  
  return none(NimNode)

proc validateRoute(name: ThreadName, procDef: NimNode) =
  procDef.assertKind(nnkProcDef)
  let firstParamTypeName = procDef.firstParamType.typeName
  
  if not name.hasTypeOfName(firstParamTypeName):
    error(fmt"Failed to register proc '{procDef.name}'. No matching type '{firstParamTypeName}' has been registered for '{name.string}'.")

  let procForType = getProcForType(name, firstParamTypeName)
  let isAlreadyRegistered = procForType.isSome()
  if isAlreadyRegistered:
    error(fmt"Failed to register proc '{procDef.name}' from '{procDef.lineInfo}'. A handler proc for type '{firstParamTypeName}' has already been registered for '{name.string}' at '{procForType.get().lineInfo}'")

proc addRoute*(name: ThreadName, procDef: NimNode) =
  ## Stores the nnkProcDef NimNode `procDef` for `name` in the CacheTable `routes`.
  ## Raises a compile-time error if:
  ## - No type was registered matching the first parameter type of procDef
  ## - A handler proc with the same first parameter type was already registered for `name`
  procDef.assertKind(nnkProcDef, "You need a proc definition to add a route in order to extract the first parameter")
  
  validateRoute(name, procDef)
  
  let name = name.string
  let isFirstRoute = not routes.hasKey(name)
  if isFirstRoute:
    routes[name] = newStmtList()
  
  routes[name].add(procDef)
    
proc hasRoutes*(name: ThreadName): bool =
  name.getRoutes().len > 0

proc hasTypes*(name: ThreadName): bool =
  name.getTypes().len > 0

proc getRegisteredThreadnames*(): seq[ThreadName] =
  ## Fetches all threads for which either types or handler procs were registered.
  for key, _ in routes:
    let name = key.ThreadName
    if name notin result:
      result.add(name)

  for key, _ in types:
    let name = key.ThreadName
    if name notin result:
      result.add(name)
