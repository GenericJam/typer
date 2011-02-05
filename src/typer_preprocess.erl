%% -*- erlang-indent-level: 2 -*-
%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2006-2011. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%

-module(typer_preprocess).

-export([get_all_files/2]).

-include("typer.hrl").

%%----------------------------------------------------------------------------

-spec get_all_files(#args{}, 'analysis' | 'trust') -> [file:filename()].

get_all_files(#args{files=Fs,files_r=Ds}, analysis) ->
  case files_and_dirs(Fs, Ds, fun test_erl_file_exclude_ann/1) of
    [] -> typer:error("no file(s) to analyze");
    AllFiles -> AllFiles
  end;
get_all_files(#args{trusted=Fs}, trust) -> 
  files_and_dirs(Fs, [], fun test_erl_file/1).

-spec test_erl_file_exclude_ann(file:filename()) -> boolean().

test_erl_file_exclude_ann(File) ->
  case filename:extension(File) of
    ".erl" -> %% Exclude files ending with ".ann.erl"
      case re:run(File, "[\.]ann[\.]erl$") of
	{match, _} -> false;
	nomatch -> true
      end;
    _ -> false
  end.

-spec test_erl_file(file:filename()) -> boolean().

test_erl_file(File) ->
  filename:extension(File) =:= ".erl".

-spec files_and_dirs([file:filename()], [file:filename()],
		     fun((file:filename()) -> boolean())) -> [file:filename()].

files_and_dirs(File_Dir, Dir_R, Fun) ->
  All_File_1 = process_file_and_dir(File_Dir, Fun),
  All_File_2 = process_dir_rec(Dir_R, Fun),
  remove_dup(All_File_1 ++ All_File_2).

-spec process_file_and_dir([file:filename()],
			   fun((file:filename()) -> boolean())) -> [file:filename()].

process_file_and_dir(File_Dir, TestFun) ->
  Fun =
    fun (Elem, Acc) ->
	case filelib:is_regular(Elem) of
	  true  -> process_file(Elem, TestFun, Acc);
	  false -> check_dir(Elem, false, Acc, TestFun)
	end
    end,
  lists:foldl(Fun, [], File_Dir).

-spec process_dir_rec([file:filename()],
		      fun((file:filename()) -> boolean())) -> [file:filename()].

process_dir_rec(Dirs, TestFun) ->
  Fun = fun (Dir, Acc) -> check_dir(Dir, true, Acc, TestFun) end,
  lists:foldl(Fun, [], Dirs).

-spec check_dir(file:filename(), boolean(), [file:filename()],
		fun((file:filename()) -> boolean())) -> [file:filename()].

check_dir(Dir, Recursive, Acc, Fun) ->
  case file:list_dir(Dir) of
    {ok, Files} ->
      {TmpDirs, TmpFiles} = split_dirs_and_files(Files, Dir),
      case Recursive of
	false ->
	  FinalFiles = process_file_and_dir(TmpFiles, Fun),
	  Acc ++ FinalFiles;
	true ->
	  TmpAcc1 = process_file_and_dir(TmpFiles, Fun),
	  TmpAcc2 = process_dir_rec(TmpDirs, Fun),
	  Acc ++ TmpAcc1 ++ TmpAcc2
      end;
    {error, eacces} ->
      typer:error("no access permission to dir \""++Dir++"\"");
    {error, enoent} ->
      typer:error("cannot access "++Dir++": No such file or directory");
    {error, _Reason} ->
      typer:error("error involving a use of file:list_dir/1")
  end.

%% Same order as the input list
-spec process_file(file:filename(), fun((file:filename()) -> boolean()), [file:filename()]) -> [file:filename()].

process_file(File, TestFun, Acc) ->
  case TestFun(File) of
    true  -> Acc ++ [File];
    false -> Acc
  end.

%% Same order as the input list
-spec split_dirs_and_files([file:filename()], file:filename()) -> {[file:filename()], [file:filename()]}.

split_dirs_and_files(Elems, Dir) ->
  Test_Fun =
    fun (Elem, {DirAcc, FileAcc}) ->
	File = filename:join(Dir, Elem),
	case filelib:is_regular(File) of
	  false -> {[File|DirAcc], FileAcc}; 
	  true  -> {DirAcc, [File|FileAcc]}
	end
    end,
  {Dirs, Files} = lists:foldl(Test_Fun, {[], []}, Elems),
  {lists:reverse(Dirs), lists:reverse(Files)}.  

%%-----------------------------------------------------------------------
%% Utilities
%%-----------------------------------------------------------------------

%% Removes duplicate filenames but it keeps the order of the input list

-spec remove_dup([file:filename()]) -> [file:filename()].

remove_dup(Files) ->
  Test_Dup = fun (File, Acc) ->
		 case lists:member(File, Acc) of
		   true  -> Acc;
		   false -> [File|Acc]
		 end
	     end,
  Reversed_Elems = lists:foldl(Test_Dup, [], Files),
  lists:reverse(Reversed_Elems).
