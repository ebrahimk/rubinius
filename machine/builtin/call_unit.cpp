#include "arguments.hpp"
#include "call_frame.hpp"
#include "object_utils.hpp"
#include "memory.hpp"

#include "builtin/call_unit.hpp"
#include "builtin/class.hpp"
#include "builtin/location.hpp"

namespace rubinius {
  CallUnit* CallUnit::create_constant_value(STATE, Object* self, Object* val) {
    CallUnit* pe = state->memory()->new_object<CallUnit>(state, as<Class>(self));

    pe->kind(CallUnit::eConstantValue);
    pe->value(state, val);
    pe->execute = constant_value_executor;

    return pe;
  }

  CallUnit* CallUnit::create_for_method(STATE, Object* self,
      Module* mod, Executable* exec, Symbol* name)
  {
    CallUnit* pe = state->memory()->new_object<CallUnit>(state, as<Class>(self));

    pe->kind(CallUnit::eForMethod);
    pe->module(state, mod);
    pe->executable(state, exec);
    pe->name(state, name);
    pe->execute = method_executor;

    return pe;
  }

  CallUnit* CallUnit::create_test(STATE, Object* self,
      CallUnit* cond, CallUnit* c_then, CallUnit* c_else)
  {
    CallUnit* pe = state->memory()->new_object<CallUnit>(state, as<Class>(self));

    pe->kind(CallUnit::eTest);
    pe->test_condition(state, cond);
    pe->test_then(state, c_then);
    pe->test_else(state, c_else);
    pe->execute = test_executor;

    return pe;
  }

  CallUnit* CallUnit::create_kind_of(STATE, Object* self, Module* mod, Fixnum* which) {
    CallUnit* pe = state->memory()->new_object<CallUnit>(state, as<Class>(self));

    pe->kind(CallUnit::eKindOf);
    pe->value(state, mod);
    pe->which(which->to_native());
    pe->execute = kind_of_executor;

    return pe;
  }

  Object* CallUnit::constant_value_executor(STATE,
      CallUnit* unit, Executable* exec, Module* mod, Arguments& args)
  {
    return unit->value();
  }

  Object* CallUnit::method_executor(STATE,
      CallUnit* unit, Executable* exec, Module* mod, Arguments& args)
  {
    args.set_name(unit->name());
    return unit->executable()->execute(state,
                                 unit->executable(), unit->module(), args);
  }

  Object* CallUnit::test_executor(STATE,
      CallUnit* unit, Executable* exec, Module* mod, Arguments& args)
  {
    Object* ret = unit->test_condition()->execute(
             state, unit->test_condition(), exec, mod, args);
    if(!ret) return ret;
    if(CBOOL(ret)) {
      return unit->test_then()->execute(state, unit->test_then(), exec, mod, args);
    } else {
      return unit->test_else()->execute(state, unit->test_else(), exec, mod, args);
    }
  }

  Object* CallUnit::kind_of_executor(STATE,
      CallUnit* unit, Executable* exec, Module* mod, Arguments& args)
  {
    Object* obj;
    if(unit->which() == -1) {
      obj = args.recv();
    } else if(unit->which() < (int)args.total()) {
      obj = args.get_argument(unit->which());
    } else {
      return cFalse;
    }

    if(Module* mod = try_as<Module>(unit->value())) {
      return RBOOL(obj->kind_of_p(state, mod));
    } else {
      return cFalse;
    }
  }
}
