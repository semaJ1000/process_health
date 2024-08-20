#!/path/to/perl

print <<END

   Program Name: Process Health Page

   Version: 3.1

   Description:

      This is a program that keeps track of processes
      on the lab and test servers and sends out email
      notifications if any of the processes stop working.
      The goal is that if any process is on the health
      page, it is not able to stop working quietly in
      the background.

      You should add your process to the health page if
      it is important that it is always running and you
      need to be made aware if it ever stops.

      There is 3 types of tests that are run: input,
      output, and long running. Input checks the validity
      of an input file, output ensures there is output and
      it is not too old, and long running checks to see if
      the process is currently executing on the server.

   Developers:

      James H (Co-op student) - April 16th 2024
      Tariq C - April 16th 2024

   Webpage URL:

      This will depend on which server you are working on,
      see two examples below. The webpage updates 
      information every 10 seconds.

      http://webpage.new/path/to/main_page
      http://webpage.net/path/to/main_page

   How to Use:

   To Add a process:

      Method 1:

         Go on to the process health web page and fill in
         the appropriate information about your process.

      Method 2:

         Add a section as outlined below somewhere near
         the beginning of your long running script.

         =pod PHP
         Input: /input/file/path
         Output: /output/file/path
         Long Running
         =cut PHP

         Omit input/output if they do not apply to your
         program. IT MUST HAVE AN ACTIVE PID IN PS -E 
         FOR THIS TO WORK, otherwise use method 1.

   To remove a process:

      Go on to the process health page and fill in
      either the name or id of the process to remove.
      If you have a =pod PHP section in your code be sure
      to remove it or the health page will pick it up again.

END