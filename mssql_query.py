#!/usr/bin/env python

#################################################################
# Query MSSQL Database for one or more rows
# Version 1.0.0
# Date : 2012-05-17
# Author  : William Strucke ( wstrucke@gmail.com )
# Adapted from script by Nicholas Scott ( scot0357 at gmail.com )
# Licence : GPL - http://www.fsf.org/licenses/gpl.txt
#################################################################

# Import Libraries
import pymssql, time, sys
from optparse import OptionParser, OptionGroup

# These arrays dictates what is fed to the required args.
# Space 1 :: short flag
# Space 2 :: long flag name which will also be the name of the stored variable
# Space 3 :: Help string
# Space 4 :: Default value
requiredArgs = [
                                ( '-H' , 'hostname' , 'Specify MSSQL Server Address'    , False ),
                                ( '-p' , 'port'         , 'Specify port. [Default: 1433]' , '1433'      ),
                                ( '-U' , 'user'     , 'Specify MSSQL User Name'         , False ),
                                ( '-P' , 'password' , 'Specify MSSQL Password'          , False ),
                           ]

optionalArgs = [
                                ( '-D' , 'database' , 'Specify the database to query' , 0 ),
                                ( '-q' , 'query' ,    'Provide a query to execute', 0 ),
                        ]

def errorDict( error ):
        errorTome =  {
                                        0       : "Success",
                                        -1      : "Unable to access SQL Server.",
                                        -2      : "Can access server but cannot query.",
                                        -3      : "Zero on in divisor.",
                           }
        retTome = { 'code' : 2,
                                'info' : errorTome[error],
                                'label': '',
                                }
        return retTome

# The function takes three arguments, three lists specified above, ensures
# proper input from the user and then returns a dictionary with keys of each
# variable entered correlating to their value.
def parseArgs( req , opt ):
        tome = {}
        usage = "usage: %prog -H hostname -U user -P password [-D database] [-q query_sql]"
        parser = OptionParser(usage=usage)
        # Declare Required Options
        required = OptionGroup(parser, "Required Options")
        for arg in req:
                required.add_option( arg[0] , '--' + arg[1] , help = arg[2] , default = arg[3] )
        parser.add_option_group(required)
        # Declare Optional Options
        optional = OptionGroup(parser, "Optional Options of Redundancy")
        for arg in opt:
                optional.add_option( arg[0] , '--' + arg[1], help = arg[2] , default = arg[3] )
        parser.add_option_group(optional)
        # Parse all args in options.args, convert to iterable dictionary
        ( options, args ) = parser.parse_args()
        for arg in required.option_list:
                tome[ arg.dest ] = getattr(options, arg.dest)
                if not tome[ arg.dest ]:
                        print "All arguments listed in Required Options must have a value."
                        parser.print_help()
                        sys.exit(3)
        for arg in optional.option_list:
                tome [ arg.dest ] = getattr(options, arg.dest)
        return tome

# Takes the info dictionary of the value and the return code and creates
# the return string (with performance data.)
def get_return_string( tome ):
        retcode = tome['code']
        retString = tome['info']
        if tome['label']:
                retString += '|' + tome['label'] + '=' + str(tome['value']) + tome['uom'] + ';;;;'
        return retString

# For use in actual check function. Takes an empty dictionary, the name
# of the metric being checked, the units it will have and what its value
# is. Return a dictionary with proper keys for each item.
def get_return_tome( name , units , value ):
        tome = {}
        tome['value']   = value
        tome['uom']     = units
        tome['info']    = name + " is " + str(value) + str(units)
        tome['label']   = name.replace( ' ' , '_' )
        return tome

# Connect to MSSQL database. Given hostname, port and vuser, vpassword.
def connectDB(hostname, vport, vuser, vpassword, vdb):
        try:
                conn = pymssql.connect(host = hostname + ":" + vport, user = vuser, password = vpassword, database = vdb)
                return conn
        except:
                return -1

def tquery( conn , query ):
        try:
                cur = conn.cursor()
                cur.execute(query)
                row = cur.fetchone()
                while row:
                        i = 0
                        while i < len(row):
                                sys.stdout.write("%s\t" % row[i])
                                i = i + 1
                        sys.stdout.write('\n')
                        row = cur.fetchone()
                return 0
        except:
                return -2 # Return unable to query database

def main( req , opt ):
        index = parseArgs( req , opt )
        if (index['database'] == 0): index['database'] = 'master'
        if (index['query'] == 0): index['query'] = 'SELECT 1 AS Response'
        conn  = connectDB(  index['hostname'] , index['port'] , index['user'], index['password'], index['database'] )
        if not isinstance( conn , int ):
                retTome = tquery( conn , index['query'] )
                if isinstance( retTome , dict ):
                        retTome['code'] = 0
                elif retTome != 0:
                        retTome = errorDict( retTome )
                conn.close()
        else:
                retTome = errorDict ( conn )

main( requiredArgs , optionalArgs )

