#!/bin/bash
#
#    PDF split print - Split up a PDF into chunks and print them.
#    Copyright (C) 2017  Alexander Rehbein
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Lesser General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Lesser General Public License for more details.
#
#    You should have received a copy of the GNU Lesser General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#    Author: Alexander Rehbein, rehbein.alexander@gmail.com

default_dir="$HOME/tmp/$( basename $0)""_out"
usage() {
	echo -e\
		"Usage: $( basename $0) [-h][-H][-n] PRINTER FILE CHUNK_SIZE ['printeroptions']\n"\
		"Split up a PDF into chunks and print them in Duplex mode. Useful for printers that can't\n"\
		"deal with large PDF files\n"\
		"Note: This script is not (yet) suited for printing several files in a loop.\n"\
		"Options:\n"\
		"	-n		Dry-run: Don't print files.\n"\
		"\n"\
		"Arguments:\n"\
		"	FILE			Target PDF file\n"\
		"	CHUNK_SIZE		Chunk size for splitting up the PDF file\n"\
		"	PRINTER			Target printer\n"\
		"	[printeroptions]	Options for printing. Put in '-quotes!\n"\
		"				Have to be valid lpr-options. Only those that\n"\
		"				would be given *after* the -P option are valid here. This\n"\
		"				Includes all '-o' options, except the defaults\n"\
		"				-o job-sheets(=none) -o media(=A4) -o -o sides(=two-sided-long-edge)\n"\
		"				(this is already in use)\n"\
		"				See man-page of lpr for details\n"\
		1>&2;
}

# Init for this script
dry_run=false

while getopts ":hHn" opt; do
	case "$opt" in
		hH)
			usage
			exit 0
		;;
		n)
			dry_run=true
		;;
		*)
			echo "Illegal option." >&2
			usage
			exit 1
		;;
	esac
done

shift $(($OPTIND -1))


if [[ $# != 3 && $# != 4 ]]; then
	echo "Error: Invalid number of arguments ($# arguments provided)" >&2
	usage
	exit 1;
fi

# Simple input argument check
arguments_good=true

if ! [[ -f $2 ]]; then
	echo "Error: Couldn't read file: $2" >&2
	arguments_good=false
fi

integer_regex='^[1-9][0-9]?+$'
if ! [[ $3 =~ $integer_regex ]]; then
	echo "Error:  argument is not an integer > 0"
	arguments_good=false
fi

if [[ $arguments_good == false ]]; then
	echo "Bad arguments. Exiting" >&2
	exit 1;
fi

# Input argument checks are over
printer="$1"
pdf_input_file="$2"
chunk_size="$3"
lpr_options=""
if [[ $# == 4 ]]; then
	lpr_options="$4"
fi
	
if ! [[ -d $default_dir ]]; then
	mkdir -p "$default_dir"
fi

if [[ $dry_run == true ]]; then
	echo "Performing dry run..."
fi

pages_total=$(pdfinfo -- "$pdf_input_file" 2> /dev/null | awk '$1 == "Pages:" {print $2}')
whole_chunks=$((pages_total / chunk_size))
leftover_chunksize=$((whole_chunks % chunk_size))
filename_no_suffix=${pdf_input_file%.pdf}

# Create files that constitute the splitting
declare -a pdf_splitting
counter=0
pdftk_return_value=0
while [[ $whole_chunks -gt $counter && $pdftk_return_value -eq 0 ]]; do 
	start=$((counter*chunk_size + 1));
	end=$((start + chunk_size - 1));
	counterstring=$(printf %04d "$counter")
	pdf_splitting[$counter]="$default_dir/${filename_no_suffix}_${counterstring}.pdf"
	pdftk "$pdf_input_file" cat "${start}-${end}" output "${pdf_splitting[$counter]}"
	pdftk_return_value=$?
	counter=$((counter + 1))
done
if [[ $leftover_chunksize -ne 0 ]]; then
	start=$((counter*chunk_size + 1));
	end=$((start + leftover_chunksize - 1));
	counterstring=$(printf %04d "$counter")
	pdf_splitting[$counter]="$default_dir/${filename_no_suffix}_${counterstring}.pdf"
	pdftk "$pdf_input_file" cat "${start}-${end}" output "${pdf_splitting[$counter]}"
	pdftk_return_value=$?
fi

if [[ $dry_run == true ]]; then
	echo "Splitting files saved to $default_dir" 
	exit 0;
else
	lpstat -p $1 > /dev/null 2>&1
	if ! [[ $? == 0 ]]; then
		echo "Error: Printer $1 not reachable"
		exit 1
	fi
	printer="$1"
	# Print first paper with job sheet
	lpr -P $printer -o sides=two-sided-long-edge $lpr_options "${pdf_splitting[0]}"
	for ((i=1; i<${#pdf_splitting[@]}; ++i)); do
		lpr -P $printer -o job-sheets=none -o media=A4 -o sides=two-sided-long-edge $lpr_options "${pdf_splitting[$i]}"
	done;
	for ((i=0; i<${#pdf_splitting[@]}; ++i)); do
		rm "${pdf_splitting[$i]}" > /dev/null 2>&1
	done;
	# If the directory has been emptied, delete it, otherwise, we don't care
	rmdir "$default_dir" > /dev/null 2>&1
fi

#else
#fi

unset pdf_splitting
