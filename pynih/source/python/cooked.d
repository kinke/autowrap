/**
   Helper functions to interact with the Python C API
 */
module python.cooked;


import python.raw;
import python.boilerplate: Module, CFunctions, Aggregates;


/**
   Creates a Python3 module from the given C functions.
   Each function has the same name in Python.
 */
auto createModule(Module module_, alias cfunctions, alias aggregates = Aggregates!())()
    if(is(cfunctions == CFunctions!F, F...) &&
       is(aggregates == Aggregates!T, T...))
{
    static assert(isPython3, "Python2 no longer supported");

    static PyModuleDef moduleDef;

    auto pyMethodDefs = cFunctionsToPyMethodDefs!(cfunctions);
    moduleDef = pyModuleDef(module_.name.ptr, null /*doc*/, -1 /*size*/, pyMethodDefs);

    auto module_ = pyModuleCreate(&moduleDef);
    addModuleTypes!aggregates(module_);

    return module_;
}


private void addModuleTypes(alias aggregates)(PyObject* module_) {
    import autowrap.common: AlwaysTry;
    import python.type: PythonType;
    import std.traits: fullyQualifiedName;

    static foreach(T; aggregates.Types) {

        static if(AlwaysTry || __traits(compiles, PythonType!T.pyType)) {
            if(PyType_Ready(PythonType!T.pyType) < 0)
                throw new Exception("Could not get type ready for `" ~ __traits(identifier, T) ~ "`");

            pyIncRef(PythonType!T.pyObject);
            PyModule_AddObject(module_, __traits(identifier, T), PythonType!T.pyObject);
        } else
            pragma(msg, "WARNING: could not wrap aggregate ", fullyQualifiedName!T);
    }
}

///  Returns a PyMethodDef for each cfunction.
private PyMethodDef* cFunctionsToPyMethodDefs(alias cfunctions)()
    if(is(cfunctions == CFunctions!(A), A...))
{
    // +1 due to the sentinel that Python uses to know when to
    // stop incrementing through the pointer.
    static PyMethodDef[cfunctions.length + 1] methods;

    static foreach(i, function_; cfunctions.functions) {{
        alias cfunction = function_.symbol;
        static assert(is(typeof(&cfunction): PyCFunction) ||
                      is(typeof(&cfunction): PyCFunctionWithKeywords),
                      __traits(identifier, cfunction) ~ " is not a Python C function");

        methods[i] = pyMethodDef!(function_.identifier)(cast(PyCFunction) &cfunction);
    }}

    return &methods[0];
}


/**
   Helper function to get around the C syntax problem with
   PyModuleDef_HEAD_INIT - it doesn't compile in D.
*/
private auto pyModuleDef(A...)(auto ref A args) {
    import std.functional: forward;

    return PyModuleDef(
        // the line below is a manual D version expansion of PyModuleDef_HEAD_INIT
        PyModuleDef_Base(PyObject(1 /*ref count*/, null /*type*/), null /*m_init*/, 0/*m_index*/, null/*m_copy*/),
        forward!args
    );
}

/**
   Helper function to create PyMethodDef structs.
   The strings are compile-time parameters to avoid passing GC-allocated memory
   to Python (by calling std.string.toStringz or manually appending the null
   terminator).
 */
auto pyMethodDef(string name, int flags = defaultMethodFlags, string doc = "", F)
                (F cfunction) pure
{
    import std.traits: ReturnType, Parameters, isPointer;
    import std.meta: allSatisfy;

    static assert(isPointer!(ReturnType!F),
                  "C function method implementation must return a pointer");
    static assert(allSatisfy!(isPointer, Parameters!F),
                  "C function method implementation must take pointers");
    static assert(Parameters!F.length == 2 || Parameters!F.length == 3,
                  "C function method implementation must take 2 or 3 pointers");

    return PyMethodDef(name.ptr, cast(PyCFunction) cfunction, flags, doc.ptr);
}


enum defaultMethodFlags = MethodArgs.Var | MethodArgs.Keywords;
