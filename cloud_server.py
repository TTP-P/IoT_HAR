#!/usr/bin/env python3
import json
import os

from flask import Flask, jsonify, request
import numpy as np

try:
    from tflite_runtime.interpreter import Interpreter
except ImportError:  # pragma: no cover - fallback when tflite_runtime is unavailable
    from tensorflow.lite import Interpreter


BASE_DIR = os.path.dirname(os.path.abspath(__file__))

HAR_MODEL_PATH = os.path.join(
    BASE_DIR, "model", "har", "final_model.tflite"
)
HAR_LABELS_PATH = os.path.join(
    BASE_DIR, "model", "har", "HAR_CNN_labels.json"
)
SSC_MODEL_PATH = os.path.join(
    BASE_DIR, "model", "ssc", "final_model.tflite"
)
SSC_LABELS_PATH = os.path.join(BASE_DIR, "model", "ssc", "labels.json")


HAR_INPUT_SIZE = 25
HAR_NUM_FEATURES = 25
HAR_OUTPUT_SIZE = 11
HAR_MEDIAN_KERNEL_LARGE = 5
HAR_MEDIAN_KERNEL_SMALL = 3
HAR_PROBABILITY_WINDOW = 5
HAR_EPS = 1e-8
HAR_LOW_CONF_THRESHOLD = 0.4

HAR_FEATURE_KEYS = [
    "accelX",
    "accelY",
    "accelZ",
    "gravityX",
    "gravityY",
    "gravityZ",
    "linAccX",
    "linAccY",
    "linAccZ",
    "accelMag",
    "linAccMag",
    "jerkMag",
    "jerkVert",
    "jerkHorizMag",
    "jerk_rms",
    "jerk_instability",
    "vert_energy_ratio",
    "horiz_energy_ratio",
    "highfreq_ratio",
    "gait_periodicity",
    "stride_variability",
    "movement_consistency",
    "vert_velocity_signed",
    "vert_velocity_trend",
    "lateral_balance",
]

HAR_FEATURE_MEAN = [
    -0.021668165922164917,
    -0.6572025418281555,
    0.03427287936210632,
    -0.02103836089372635,
    -0.6578264236450195,
    0.0361427366733551,
    -0.0006298051448538899,
    0.0006239209324121475,
    -0.0018698560306802392,
    1.0219208002090454,
    0.24593454599380493,
    0.29173874855041504,
    -0.0002578217536211014,
    0.1820693016052246,
    0.3361179828643799,
    0.16432751715183258,
    0.9315782785415649,
    0.06842168420553207,
    16.487808227539062,
    -0.10400755703449249,
    0.18963348865509033,
    0.9839140772819519,
    19.41428565979004,
    0.0008267218945547938,
    121.81930541992188,
]

HAR_FEATURE_SCALE = [
    0.4349856376647949,
    0.5218822956085205,
    0.49425432085990906,
    0.381322979927063,
    0.4149784445762634,
    0.4564850628376007,
    0.2155025750398636,
    0.3259219825267792,
    0.19245800375938416,
    0.3083796501159668,
    0.35948166251182556,
    0.47981226444244385,
    0.42215633392333984,
    0.3224376440048218,
    0.44908982515335083,
    0.21452125906944275,
    0.17211775481700897,
    0.1721177101135254,
    1302.8140869140625,
    0.3030170500278473,
    0.24368108808994293,
    0.024226132780313492,
    2.092092990875244,
    0.45464491844177246,
    50129.30078125,
]

HAR_DEFAULT_LABELS = [
    "Ascending stairs",
    "Descending stairs",
    "Lying back",
    "Lying left",
    "Lying right",
    "Lying stomach",
    "Miscellaneous movements",
    "Normal walking",
    "Running",
    "Shuffle walking",
    "Sitting / Standing",
]

HAR_LABEL_DISPLAY_MAP = {
    "ascending": "Ascending stairs",
    "descending": "Descending stairs",
    "lyingBack": "Lying back",
    "lyingLeft": "Lying left",
    "lyingRight": "Lying right",
    "lyingStomach": "Lying stomach",
    "miscMovement": "Miscellaneous movements",
    "normalWalking": "Normal walking",
    "running": "Running",
    "shuffleWalking": "Shuffle walking",
    "sittingStanding": "Sitting / Standing",
}

HAR_MISC_INDEX = 6
HAR_SHUFFLE_INDEX = 9
HAR_LOW_CONF_CLASSES = {HAR_MISC_INDEX, HAR_SHUFFLE_INDEX}

SSC_INPUT_SIZE = 50
SSC_NUM_FEATURES = 19
SSC_NUM_CLASSES = 4
SSC_EPS = 1e-6
SSC_TAU_NON = 0.55
SSC_TAU_OTHER = 0.45
SSC_SMOOTH_WINDOW = 5

SSC_FEATURE_KEYS = [
    "accelX",
    "accelY",
    "accelZ",
    "accelMag",
    "linAccMag",
    "jerkMag",
    "jerk_rms",
    "breathing_stability",
    "rhythm_stability",
    "burst_density",
    "energy_burst_ratio",
    "breathing_intensity_var",
    "fft_energy",
    "zero_cross_rate",
    "dominant_resp_freq",
    "cough_energy_ratio",
    "breathing_disruption",
    "spectral_sharpness",
    "short_energy_ratio",
]

SSC_FEATURE_MEAN = [
    -0.08374115079641342,
    -0.3860498368740082,
    0.06338915973901749,
    1.0106374025344849,
    0.04170093685388565,
    0.04655652865767479,
    0.05512155964970589,
    0.9715603590011597,
    0.9740087985992432,
    0.03951224684715271,
    1.0593878030776978,
    0.848936140537262,
    0.9964520931243896,
    0.02270447462797165,
    0.6663512587547302,
    1.0388972759246826,
    0.00020785958622582257,
    0.1464998871088028,
    1.018700361251831,
]

SSC_FEATURE_SCALE = [
    0.5173215270042419,
    0.4534896910190582,
    0.6255550980567932,
    0.057191021740436554,
    0.05241154879331589,
    0.07199607789516449,
    0.066088005900383,
    0.03903094306588173,
    0.030964549630880356,
    0.09328233450651169,
    0.8716886639595032,
    0.1532822996377945,
    0.006252311170101166,
    0.06950970739126205,
    0.5617320537567139,
    0.7242363095283508,
    0.004739460069686174,
    0.061410170048475266,
    0.47068580985069275,
]

SSC_DEFAULT_LABELS = [
    "breathingNormally",
    "coughing",
    "hyperventilation",
    "other",
]


def _argmax(values):
    best_index = 0
    best_value = values[0]
    for i in range(1, len(values)):
        if values[i] > best_value:
            best_value = values[i]
            best_index = i
    return best_index


def _median(values):
    sorted_values = sorted(values)
    return sorted_values[len(sorted_values) // 2]


def _mode(values):
    if not values:
        return 0
    counts = {}
    for value in values:
        counts[value] = counts.get(value, 0) + 1
    best_value = values[-1]
    best_count = -1
    for key, count in counts.items():
        if count > best_count or (count == best_count and key == values[-1]):
            best_value = key
            best_count = count
    return best_value


def _average_probabilities(history, size):
    accum = [0.0] * size
    for row in history:
        for i in range(size):
            accum[i] += row[i]
    divisor = float(len(history))
    for i in range(size):
        accum[i] /= divisor
    return accum


class HarEngine:
    def __init__(self, model_path, labels_path):
        self._interpreter = Interpreter(model_path=model_path)
        self._interpreter.allocate_tensors()
        input_details = self._interpreter.get_input_details()
        output_details = self._interpreter.get_output_details()
        self._input_index = input_details[0]["index"]
        self._output_index = output_details[0]["index"]

        self._feature_buffer = []
        self._raw_prediction_history = []
        self._confidence_adjusted_history = []
        self._probability_history = []
        self._last_confidence_adjusted_class = None

        self._labels = self._load_labels(labels_path)
        self.latest_prediction_text = None
        self.latest_label = None
        self.latest_confidence = 0.0

    def _load_labels(self, labels_path):
        labels = list(HAR_DEFAULT_LABELS)
        try:
            with open(labels_path, "r", encoding="utf-8") as handle:
                decoded = json.load(handle)
            if isinstance(decoded, list) and len(decoded) == HAR_OUTPUT_SIZE:
                mapped = []
                for label in decoded:
                    mapped.append(HAR_LABEL_DISPLAY_MAP.get(label, label))
                labels = mapped
        except Exception:
            labels = list(HAR_DEFAULT_LABELS)
        return labels

    def add_sample(self, feature_map, is_step_boundary):
        row = [feature_map.get(key, 0.0) for key in HAR_FEATURE_KEYS]
        self._feature_buffer.append(row)
        if len(self._feature_buffer) > HAR_INPUT_SIZE:
            self._feature_buffer.pop(0)

        if not is_step_boundary or len(self._feature_buffer) < HAR_INPUT_SIZE:
            return

        self._run_inference()

    def _run_inference(self):
        window = self._feature_buffer[-HAR_INPUT_SIZE:]
        scaled = []
        for row in window:
            scaled_row = []
            for j in range(HAR_NUM_FEATURES):
                scale = HAR_FEATURE_SCALE[j]
                if abs(scale) < HAR_EPS:
                    scale = 1.0
                scaled_row.append((row[j] - HAR_FEATURE_MEAN[j]) / scale)
            scaled.append(scaled_row)

        input_data = np.array([scaled], dtype=np.float32)
        self._interpreter.set_tensor(self._input_index, input_data)
        self._interpreter.invoke()
        output = self._interpreter.get_tensor(self._output_index)

        probabilities = list(output[0])
        raw_class = _argmax(probabilities)
        raw_confidence = probabilities[raw_class]

        self._raw_prediction_history.append(raw_class)
        if len(self._raw_prediction_history) > HAR_MEDIAN_KERNEL_LARGE:
            self._raw_prediction_history.pop(0)
        step1_class = _median(self._raw_prediction_history)

        step2_class = step1_class
        if (
            raw_confidence < HAR_LOW_CONF_THRESHOLD
            and step1_class in HAR_LOW_CONF_CLASSES
            and self._last_confidence_adjusted_class is not None
        ):
            step2_class = self._last_confidence_adjusted_class
        self._last_confidence_adjusted_class = step2_class

        self._confidence_adjusted_history.append(step2_class)
        if len(self._confidence_adjusted_history) > HAR_MEDIAN_KERNEL_SMALL:
            self._confidence_adjusted_history.pop(0)
        step3_class = _median(self._confidence_adjusted_history)

        self._probability_history.append(probabilities)
        if len(self._probability_history) > HAR_PROBABILITY_WINDOW:
            self._probability_history.pop(0)
        smoothed = _average_probabilities(
            self._probability_history, HAR_OUTPUT_SIZE
        )
        soft_class = _argmax(smoothed)

        final_class = soft_class if soft_class == HAR_MISC_INDEX else step3_class

        self.latest_confidence = smoothed[final_class]
        if final_class < len(self._labels):
            label = self._labels[final_class]
        else:
            label = f"Class {final_class}"
        self.latest_label = label
        self.latest_prediction_text = f"{label} ({self.latest_confidence * 100:.1f}%)"

    def buffer_size(self):
        return len(self._feature_buffer)

    def reset(self):
        self._feature_buffer = []
        self._raw_prediction_history = []
        self._confidence_adjusted_history = []
        self._probability_history = []
        self._last_confidence_adjusted_class = None
        self.latest_prediction_text = None
        self.latest_label = None
        self.latest_confidence = 0.0


class SscEngine:
    def __init__(self, model_path, labels_path):
        self._interpreter = Interpreter(model_path=model_path)
        self._interpreter.allocate_tensors()
        input_details = self._interpreter.get_input_details()
        output_details = self._interpreter.get_output_details()
        self._input_index = input_details[0]["index"]
        self._output_index = output_details[0]["index"]

        self._feature_buffer = []
        self._prediction_history = []
        self._labels = self._load_labels(labels_path)

        self.latest_label = None
        self.latest_confidence = 0.0

    def _load_labels(self, labels_path):
        labels = list(SSC_DEFAULT_LABELS)
        try:
            with open(labels_path, "r", encoding="utf-8") as handle:
                decoded = json.load(handle)
            if isinstance(decoded, list) and len(decoded) == SSC_NUM_CLASSES:
                labels = decoded
        except Exception:
            labels = list(SSC_DEFAULT_LABELS)
        return labels

    def add_sample(self, feature_map):
        row = [feature_map.get(key, 0.0) for key in SSC_FEATURE_KEYS]
        self._feature_buffer.append(row)
        if len(self._feature_buffer) > SSC_INPUT_SIZE:
            self._feature_buffer.pop(0)

        if len(self._feature_buffer) < SSC_INPUT_SIZE:
            return

        self._run_inference()

    def _run_inference(self):
        window = self._feature_buffer[-SSC_INPUT_SIZE:]
        scaled = []
        for row in window:
            scaled_row = []
            for j in range(SSC_NUM_FEATURES):
                scale = SSC_FEATURE_SCALE[j]
                if abs(scale) < SSC_EPS:
                    scale = 1.0
                scaled_row.append((row[j] - SSC_FEATURE_MEAN[j]) / scale)
            scaled.append(scaled_row)

        input_data = np.array([scaled], dtype=np.float32)
        self._interpreter.set_tensor(self._input_index, input_data)
        self._interpreter.invoke()
        output = self._interpreter.get_tensor(self._output_index)

        probabilities = list(output[0])
        decided_class = self._two_stage_decision(probabilities)
        self._prediction_history.append(decided_class)
        if len(self._prediction_history) > SSC_SMOOTH_WINDOW:
            self._prediction_history.pop(0)
        class_index = _mode(self._prediction_history)

        if class_index < len(self._labels):
            self.latest_label = self._labels[class_index]
        else:
            self.latest_label = f"Class {class_index}"
        if class_index < len(probabilities):
            self.latest_confidence = probabilities[class_index]
        else:
            self.latest_confidence = 0.0

    def _two_stage_decision(self, probabilities):
        if not self._labels:
            return _argmax(probabilities)
        try:
            other_index = self._labels.index("other")
        except ValueError:
            other_index = -1
        if other_index == -1:
            return _argmax(probabilities)

        best_non_other_value = -1.0
        best_non_other_index = -1
        for i in range(len(probabilities)):
            if i == other_index:
                continue
            value = probabilities[i]
            if value > best_non_other_value:
                best_non_other_value = value
                best_non_other_index = i

        other_prob = probabilities[other_index] if other_index < len(probabilities) else 0.0
        if best_non_other_index == -1:
            return other_index
        low_confidence = best_non_other_value < SSC_TAU_NON
        other_dominates = other_prob > SSC_TAU_OTHER
        if low_confidence and other_dominates:
            return other_index
        return best_non_other_index

    def reset(self):
        self._feature_buffer = []
        self._prediction_history = []
        self.latest_label = None
        self.latest_confidence = 0.0


app = Flask(__name__)

har_engine = HarEngine(HAR_MODEL_PATH, HAR_LABELS_PATH)
ssc_engine = SscEngine(SSC_MODEL_PATH, SSC_LABELS_PATH)


@app.route("/predict", methods=["POST"])
def predict():
    payload = request.get_json(silent=True) or {}
    samples = payload.get("samples", [])

    for sample in samples:
        har_features = sample.get("har", {})
        ssc_features = sample.get("ssc", {})
        is_step_boundary = bool(sample.get("is_step_boundary", False))
        har_engine.add_sample(har_features, is_step_boundary)
        ssc_engine.add_sample(ssc_features)

    return jsonify(
        {
            "har_label": har_engine.latest_label,
            "har_display": har_engine.latest_prediction_text,
            "har_confidence": har_engine.latest_confidence,
            "har_buffer_size": har_engine.buffer_size(),
            "ssc_label": ssc_engine.latest_label,
            "ssc_confidence": ssc_engine.latest_confidence,
        }
    )


@app.route("/reset", methods=["POST"])
def reset():
    har_engine.reset()
    ssc_engine.reset()
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
