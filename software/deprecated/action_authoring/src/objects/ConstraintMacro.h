#ifndef CONSTRAINT_MACRO_H
#define CONSTRAINT_MACRO_H

#include <string>
#include <vector>
#include <boost/unordered_map.hpp>
#include <lcm/lcm-cpp.hpp>
#include <lcmtypes/drc_lcmtypes.hpp>

#include "ConstraintMacro.h"
#include "AtomicConstraint.h"

namespace action_authoring
{

class InvalidMethodCallForContraintTypeException : public std::runtime_error
{
public:
    InvalidMethodCallForContraintTypeException(const std::string &msg) : std::runtime_error(msg) {};
};

/**todo: add comment / description*/
class ConstraintMacro
{

    //----------enumerations
public:
    typedef enum
    {
        ATOMIC, //todo: add small comment
        SEQUENTIAL //
    }
    ConstraintMacroType;

    //------------fields--------
private:
    std::string _name;
    std::vector<boost::shared_ptr<ConstraintMacro> > _constraints;
    const ConstraintMacroType _constraintType;
    const AtomicConstraintPtr _atomicConstraint;
    double _timeLowerBound;
    double _timeUpperBound;

    //-------Constructors--
public:
    ConstraintMacro(const std::string &name, const ConstraintMacroType &constraintType);
    ConstraintMacro(const std::string &name, AtomicConstraintPtr atomicConstraint);

    //Accessors
    std::string getName() const
    {
        return _name;
    };
    void setName(std::string name)
    {
        _name = name;
    };
    double getTimeLowerBound()
    {
        if (_constraintType == ConstraintMacro::ATOMIC)
        {
            return _atomicConstraint->getTimeLowerBound();
        } else 
        {
            return _timeLowerBound;
        }
    }
    double getTimeUpperBound()
    {
        if (_constraintType == ConstraintMacro::ATOMIC)
        {
            return _atomicConstraint->getTimeUpperBound();
        } else
        {
            return _timeUpperBound;
        }
    }
    void setTimeLowerBound(double t)
    {
        if (_constraintType == ConstraintMacro::ATOMIC)
        {
            _atomicConstraint->setTimeLowerBound(t);
        } else
        {
            _timeLowerBound = t;
        }
    }
    void setTimeUpperBound(double t)
    {
        if (_constraintType == ConstraintMacro::ATOMIC)
        {
            _atomicConstraint->setTimeUpperBound(t);
        } else
        {
            _timeUpperBound = t;
        }
    }

    ConstraintMacroType getConstraintMacroType() const
    {
        return _constraintType;
    };

    //Available for non-ATOMIC constraints only
    void getConstraintMacros(std::vector <
                             boost::shared_ptr<ConstraintMacro> > &constraints) const;

    void appendConstraintMacro(boost::shared_ptr<ConstraintMacro> constraint);

    //Available for ATOMIC constraints only
    AtomicConstraintPtr getAtomicConstraint() const;

    std::vector<drc::contact_goal_t> toLCM();
}; //class ConstraintMacro

typedef boost::shared_ptr<ConstraintMacro> ConstraintMacroPtr;
typedef boost::shared_ptr<const ConstraintMacro> ConstraintMacroConstPtr;
} //namespace action_authoring


#endif //CONSTRAINT_MACRO_H