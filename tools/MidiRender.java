import com.sun.media.sound.AudioSynthesizer;
import java.io.File;
import java.util.*;
import javax.sound.midi.*;
import javax.sound.sampled.*;

/** Offline General MIDI render using the installed JDK's software synthesizer. */
public final class MidiRender {
    record Timed(MidiEvent event, int order) {}
    public static void main(String[] args) throws Exception {
        Sequence sequence = MidiSystem.getSequence(new File(args[0]));
        if (sequence.getDivisionType() != Sequence.PPQ)
            throw new IllegalArgumentException("Only PPQ MIDI is supported");
        Synthesizer synth = MidiSystem.getSynthesizer();
        if (!(synth instanceof AudioSynthesizer audio))
            throw new IllegalStateException("JDK software synthesizer unavailable");
        AudioFormat format = new AudioFormat(44100, 16, 2, true, false);
        AudioInputStream stream = audio.openStream(format, Map.of("interpolation", "sinc", "max polyphony", "256"));
        Soundbank bank = synth.getDefaultSoundbank();
        if (bank == null) throw new IllegalStateException("No General MIDI soundbank");
        synth.loadAllInstruments(bank);
        Receiver receiver = synth.getReceiver();
        List<Timed> events = new ArrayList<>();
        int order = 0;
        for (Track track : sequence.getTracks())
            for (int i = 0; i < track.size(); ++i) events.add(new Timed(track.get(i), order++));
        events.sort(Comparator.comparingLong((Timed t) -> t.event().getTick()).thenComparingInt(Timed::order));
        long previousTick = 0;
        double microseconds = 0;
        int tempo = 500000;
        for (Timed timed : events) {
            MidiEvent event = timed.event();
            microseconds += (event.getTick() - previousTick) * (double) tempo / sequence.getResolution();
            previousTick = event.getTick();
            MidiMessage message = event.getMessage();
            if (message instanceof MetaMessage meta) {
                if (meta.getType() == 0x51) {
                    byte[] data = meta.getData();
                    tempo = ((data[0] & 255) << 16) | ((data[1] & 255) << 8) | (data[2] & 255);
                }
            } else receiver.send(message, (long) microseconds);
        }
        long frames = (long) ((microseconds / 1_000_000.0 + 1.0) * format.getFrameRate());
        try (AudioInputStream limited = new AudioInputStream(stream, format, frames)) {
            AudioSystem.write(limited, AudioFileFormat.Type.WAVE, new File(args[1]));
        } finally { receiver.close(); synth.close(); }
        System.out.printf(Locale.ROOT, "%s: %.3f seconds, %s%n", args[0], frames / format.getFrameRate(), bank.getName());
    }
}
