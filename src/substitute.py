#!/usr/bin/python

import argparse
import os
import re
import subprocess
import sys

def str2bool(v):
    if v.lower() in ('yes', 'true', 't', 'y', '1'):
        return True
    elif v.lower() in ('no', 'false', 'f', 'n', '0'):
        return False
    else:
        raise argparse.ArgumentTypeError('Boolean value expected.')

def update_dict_from_file(filePath, subs, var_source, sensitive):
    print "\nLoading values from: {0}".format(filePath)
    f = open(filePath, 'rw')
    for line in f:
        if not line:
            # empty string
            continue
        if "=" not in line:
            print("Found line in {0} conf file that was not formatted like key=value. Line was: {1}".format(filePath, line))
            continue
        k, v = line.strip().split('=')
        existing_value_printable = subs.get("xxxxxx" if sensitive else k, "Not set")
        new_value_printable = "xxxxxx" if sensitive else v
        print("{0} substitutions override {1}, {2} => {3}".format(var_source, k, existing_value_printable, new_value_printable))
        subs[k.strip()] = v.strip()
    f.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Perform variable substititions")
    parser.add_argument('-s', '--subsdir', help="The directory containing the subsitution files", required=True)
    parser.add_argument('-r', '--replacementsdir', help="The directory containing files where substitutions should be made", required=True)
    parser.add_argument('-e', '--environment', help="The environment to use for substitutions.", required=True)
    parser.add_argument('-l', '--local', type=str2bool, help="Is running in local development, won't use Ocotpus variables", default=False)
    args = parser.parse_args()

    defaults_file = '{0}/Default.conf'.format(args.subsdir)
    subs = {
        'ENVIRONMENT': args.environment
    }
    update_dict_from_file(defaults_file, subs, "Default", False)

    if args.environment != "Default":
        env_file = '{0}/{1}.conf'.format(args.subsdir, args.environment)
        update_dict_from_file(env_file, subs, args.environment, False)

    sensitive_file_choice = "Local" if args.local else "Octopus"
    sensitive_file_path = "{0}/Sensitive.{1}.conf".format(args.subsdir, sensitive_file_choice)
    if not os.path.isfile(sensitive_file_path):
        print("Did not find a file with sensitive substituions at {0}. Cannot continue".format(sensitive_file_path))
        sys.exit(-1)
    update_dict_from_file(sensitive_file_path, subs, "Sensitive", True)

    for dirpath, dirnames, filenames in os.walk(args.replacementsdir):
        for file in filenames:
            file = os.path.join(dirpath, file)
            tempfile = file + ".temp"
            with open(tempfile, "w") as target:
                with open(file) as source:
                    for line in source:
                        for key, value in subs.iteritems():
                            line = line.replace("@@{0}@@".format(key), value)
                        target.write(line)
            os.rename(tempfile, file)

    outfile_path = '{0}/Variables.conf'.format(args.replacementsdir)
    var_outfile = open(outfile_path, 'w')
    print "\nWriting all values to: {0}".format(outfile_path)
    for key, value in subs.iteritems():
        line = '{0}={1}\n'.format(key,value)
        var_outfile.write(line)
    var_outfile.close()

    sys.exit(0)