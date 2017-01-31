#!/bin/bash

. cmd.sh
. path.sh

echo "## LOG: $0 $@"

# begin options
nj=4
decode_nj=1
num_threads=4
doScoring=0	
use_gpu="no"
fbank16k_config_opts="--window-type=hamming --use-energy=false --sample-frequency=16000 --low-freq=64 --high-freq=8000 --dither=1 --num-mel-bins=40 --htk-compat=true"
# end options

. utils/parse_options.sh # accept options, very useful API.

function Usage {
	cat<<END
	./decoding.sh <root-dir> <graph-dir> <nnet_dir> file_id
END
}

if [ $# -ne 4 ]; then
  Usage && exit 1
fi

sysdir=$1
graphdir=$2
fbank_nnet_dir=$3
file_id=$4

for x in $fbank_nnet_dir/{final.nnet,final.mdl} $graphdir/HCLG.fst; do
	echo "## LOG ($0): found fbank features at $x" 
done

# init paths
root_dir=$lvcsrRootDir/../../
data_dir=$root_dir/data
working_dir=$data_dir/$file_id
resample_dir=$working_dir/resample
resample_file=$resample_dir/$file_id.wav
diarize_dir=$working_dir/diarization
diarize_file=$diarize_dir/$file_id.seg
[ -f $diarize_file ] || { echo "## ERROR ($0): No diarization file, exiting"; exit 1; }
transcribe_dir=$working_dir/transcript/lvcsr 
[ -d $transcribe_dir ] || mkdir -p $transcribe_dir
temp_dir=$working_dir/temp/lvcsr
[ -d $temp_dir ] || mkdir -p $temp_dir
latticedir=$temp_dir/lattice

# Kaldi segments and spk2utt files
awk '$1 !~ /^;;/ {print $8"-"$1"-"$3/100.0"-"($3+$4)/100.0" "$1" "$3/100.0" "($3+$4)/100.0}' $diarize_file | sort -nk3 > $temp_dir/segments
echo "## LOG ($0): Printing segments contents"
awk '{split($1,a,"-"); print $1" "a[1]  }'  $temp_dir/segments > $temp_dir/utt2spk
echo "## LOG ($0): Printing utt2spk contents"	
cat $temp_dir/utt2spk | utils/utt2spk_to_spk2utt.pl > $temp_dir/spk2utt
perl -e ' ($wavFile) = @ARGV; $label=$wavFile; $label =~ s/.*\///g; $label =~ s/\.wav//g;  print "$label $wavFile\n"; ' $resample_file > $temp_dir/wav.scp
cat $temp_dir/wav.scp | awk '{ print $1, $1, "1"; }' > $temp_dir/reco2file_and_channel
echo $temp_dir		
utils/validate_data_dir.sh --no-text --no-feats $temp_dir
utils/fix_data_dir.sh $temp_dir

# make_fbank_pitch
echo "## LOG ($0): make_fbank_pitch started @ `date`"
sdata=$temp_dir
data=$sdata/fbank-pitch
feat=$sdata/feat/
[ -d $data ] || mkdir -p $data
for x in $(find $sdata/ -maxdepth 1 -type f); do
	cp $x $data/
done
cp $sdata/* $data
opts="$fbank16k_config_opts"
echo "--sample-frequency=16000" > $data/pitch.conf
echo "$opts" | perl -ane 'chomp; @A = split(/\s+/); 
	for($i = 0; $i < @A; $i++) {print "$A[$i]\n";}' > $data/fbank.conf
steps/make_fbank_pitch.sh --nj $nj --cmd "$train_cmd" --fbank-config $data/fbank.conf  \
	--pitch-config $data/pitch.conf $data $feat/log $feat/data || exit 1
steps/compute_cmvn_stats.sh $data $feat/log $feat/data || exit 1
echo "## LOG ($0): make_fbank_pitch done @ `date`"

# decode
echo "## LOG ($0): decoding started @ `date`"
data=$temp_dir/fbank-pitch
[ -e $data/feats.scp ] || \
	{ echo "## ERROR ($0): feats.scp ('$data/feats.scp') is not ready !"; exit 1; }
steps/decode.sh --nj $decode_nj --cmd "$decode_cmd" \
	--acwt 0.1 --beam 10 --lattice-beam 8 --max-mem 500000000 \
	--skip-scoring true --num-threads $num_threads --srcdir $fbank_nnet_dir $graphdir $data $latticedir || exit 1
score_value=9 #??
echo "## LOG ($0): now generate ctm file @ `date`"
scoring_opts="--min-lmwt 8 --max-lmwt 15"
steps/get_ctm.sh --cmd "$decode_cmd" --model-dir $fbank_nnet_dir $scoring_opts $data $graphdir $latticedir || exit 1;
ctmfilename=`basename $data`
cp $latticedir/score_${score_value}/$ctmfilename.ctm $latticedir/$file_id.ctm
sort -nk3 $latticedir/$file_id.ctm -o $transcribe_dir/$file_id.ctm
perl utils/ctm2stm.pl $transcribe_dir/$file_id.ctm  $data/segments $transcribe_dir/$file_id.stm
echo "## LOG ($0): decoding done @ `date`"

# write_transcript
cat $transcribe_dir/$file_id.stm | awk 'var=1{$3="S1"; print $0}' > $transcribe_dir/tmp
mv $transcribe_dir/tmp $transcribe_dir/$file_id.stm
perl utils/stm2textgrid.pl $transcribe_dir/$file_id.stm
perl utils/textgrid2csv.pl $transcribe_dir/$file_id.TextGrid

echo "## LOG ($0): Completed."