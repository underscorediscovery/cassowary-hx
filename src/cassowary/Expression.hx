package cassowary;

import cassowary.Variable;
import Map;

class Expression {

    public var is_constant (get,never):Bool;
    function get_is_constant() return Lambda.count(terms) == 0;

    public var terms : OrderedMap<AbstractVariable, Float>;

    public var constant : Float = 0.0;
    public function new( ?cvar:Dynamic, ?_value:Float=1.0, ?_constant:Float=0.0) {
        terms = new OrderedMap<AbstractVariable, Float>( new Map<AbstractVariable, Float>() );
        constant = _constant;

        if(cvar != null) {
            if(Std.is(cvar, AbstractVariable)) {
                var avar:AbstractVariable = cvar;
                set_variable(avar, _value);
            } else if(Std.is(cvar, Float)) {
                var f : Float = cvar;
                if(!Math.isNaN(f)) {
                    constant = f;
                } else {
                    throw "";
                }
            }
        }
    }

    public function init_from_hash(_constant:Float, t:OrderedMap<AbstractVariable, Float>) {
        cassowary.Log._verbose("*******************************");
        cassowary.Log._verbose("clone c.initializeFromHash");
        cassowary.Log._verbose("*******************************");

        terms = null;
        constant = _constant;
        terms = new OrderedMap<AbstractVariable, Float>( new Map<AbstractVariable, Float>() );
        for(v in t.keys()) terms.set(v, t.get(v));
        return this;
    }

    // public inline function each(cb:AbstractVariable->Float->Void) {
    //     for(clv in terms.keys()) {
    //         var coeff = terms.get(clv);
    //     }
    // }

    public inline function multiply_me(x:Float) {
        constant *= x;

        for(clv in terms.keys()) {
            var coeff : Float= terms.get(clv);
            terms.set(clv, coeff * x);
        }

        return this;
    } //multiply_me

    public inline function clone() {
        cassowary.Log._verbose("*******************************");
        cassowary.Log._verbose("clone c.Expression");
        cassowary.Log._verbose("*******************************");
        return Expression.empty().init_from_hash(constant, terms);
    }

    public inline function timesf(x:Float) {
        return clone().multiply_me(x);
    }

    public inline function times(x:Expression) {
        if(is_constant) {
            return x.timesf(constant);
        } else if(x.is_constant) {
            return timesf(x.constant);
        } else {
            trace('source: $x');
            throw Error.NonExpression;
        }
    }

    public inline function plus(expr:Expression) {
        return clone().add_expr(expr,1);
    }

    public inline function plusv(cvar:Variable) {
        return clone().add_variable(cvar, 1);
    }

    public inline function minus(expr:Expression) {
        return clone().add_expr(expr,-1);
    }

    public inline function minusv(cvar:Variable) {
        return clone().add_variable(cvar, -1);
    }

    public inline function dividef(x:Float) {
        if(C.approx(x,0)) { trace('divide by zero: $x'); throw Error.NonExpression;}
        return timesf(1/x);
    }

    public inline function divide(x:Expression) {
        if(!x.is_constant) { trace('divide by non-constant source: $x'); throw Error.NonExpression; }
        return timesf(1/x.constant);
    }

    public inline function add_expr(expr:Dynamic, n:Float=1, ?subject:AbstractVariable, ?solver:Tableau) {

        var _expr:Expression = null;
        if(Std.is(expr, AbstractVariable)) {
            _expr = Expression.from_variable(expr);
        } else {
            _expr = expr;
        }

        constant += (n * _expr.constant);

        for(clv in _expr.terms.keys()) {
            var coeff = _expr.terms.get(clv);
            add_variable(clv, coeff*n, subject, solver);
        }

        return this;

    }

    public function add_variable(v:AbstractVariable, cd:Float=1.0, ?subject:AbstractVariable, ?solver:Tableau) {
        var coeff = terms.get(v);
        if(coeff != null) {
            var new_coeff = coeff+cd;
            if(new_coeff == 0 || C.approx(new_coeff,0)) {
                if(solver != null) {
                    solver.note_removed(v, subject);
                }
                terms.remove(v);
            } else {
                set_variable(v, new_coeff);
            }
        } else {
            if (!C.approx(cd, 0)) {
                set_variable(v, cd);
                if(solver != null) {
                    solver.note_added(v, subject);
                }
            }
        }

        return this;
    }

    public inline function set_variable(v:AbstractVariable, c:Float) {
        terms.set(v, c);
        return this;
    }

    public inline function any_pivotable_variable() {
        if(is_constant) throw "Expression: any_pivotable_variable called on a constant";

        var rv = null;
        for(clv in terms.keys()) {
            if(clv.is_pivotable) {
                rv = clv;
                break;
            }
        }

        return rv;

    } //any_pivotable_variable

    public inline function substitute_out(outvar:AbstractVariable, expr:Expression, ?subject:AbstractVariable, ?solver:Tableau) {

        var multiplier = terms.get(outvar);
        terms.remove(outvar);
        constant += (multiplier * expr.constant);

        for(clv in expr.terms.keys()) {
            var coeff = expr.terms.get(clv);

            var old_coeff = terms.get(clv);
            if(old_coeff != null) {
                var new_coeff = old_coeff + multiplier * coeff;
                if(C.approx(new_coeff,0)) {
                    solver.note_removed(clv, subject);
                    terms.remove(clv);
                } else {
                    terms.set(clv, new_coeff);
                }
            } else {
                terms.set(clv, multiplier*coeff);
                if(solver != null) {
                    solver.note_added(clv, subject);
                }
            }
        } //each expr.terms.keys

    } //

    public function change_subject(old_subject:AbstractVariable, nsubj:AbstractVariable) {
        set_variable(old_subject, new_subject(nsubj));
    }

    public function new_subject(subject:AbstractVariable) {
        var reciprocal = 1 / terms.get(subject);
        terms.remove(subject);
        multiply_me(-reciprocal);
        return reciprocal;
    }

    public function terms_equals(other:OrderedMap<AbstractVariable, Float>) {
        if(terms == other) return true;
        if( Lambda.count(terms) != Lambda.count(other)) return false;
        for(clv in terms.keys()) {
            var found=false;
            for(oclv in other.keys()) {
                if(oclv == clv) found = true;
            }
            if(!found) return false;
        }
        return true;
    }

    public function str() {
        return '{ constant: $constant, size:${Lambda.count(terms)}, terms: ${Std.string(terms)} }';
    }

    inline function toString() {

        var bstr = '';
        var needsplus = false;
        if(!C.approx(constant,0) || is_constant) {
            bstr += constant;
            if(is_constant) {
                return bstr;
            } else {
                needsplus = true;
            }
        }

        for(clv in terms.keys()) {
            var coeff = terms.get(clv);
            if(needsplus) bstr += ' + ';
            bstr += coeff + '*' + clv.value;
            needsplus = true;
        }

        return bstr;
    }

    public function equals(other:Expression) {
        if(this == other) return true;
        return (other.constant == constant && terms_equals(other.terms));
    }

    public function coefficient_for(clv:AbstractVariable) {
        var c = terms.get(clv);
        return c == null ? 0 : c;
    }

    public function Plus(e1:Expression, e2:Expression) {
        return e1.plus(e2);
    }

    public function Minus(e1:Expression, e2:Expression) {
        return e1.minus(e2);
    }

    public function Timesf(e1:Expression, e2:Float) {
        return e1.timesf(e2);
    }

    public function Times(e1:Expression, e2:Expression) {
        return e1.times(e2);
    }

    public function Dividef(e1:Expression, e2:Float) {
        return e1.dividef(e2);
    }

    public function Divide(e1:Expression, e2:Expression) {
        return e1.divide(e2);
    }

    public static function empty(){ return new Expression(null, 1, 0); }
    public static function from_expr(e:Dynamic){ return new Expression(null, 1, 0).add_expr(e); }
    public static function from_constant(cons:Float){ return new Expression(null,0,cons); }
    public static function from_value(v:Float){ return new Expression(null, v, 0); }
    public static function from_variable(v:Variable){ return new Expression(v,1,0); }
}
