import re
import logging
from typing import List, Dict, Any
import spacy

logger = logging.getLogger(__name__)

# Initialize spaCy
try:
    nlp = spacy.load("en_core_web_sm")
except Exception:
    nlp = spacy.blank("en")

def count_syllables(word: str) -> int:
    """Estimates the number of syllables in an English word."""
    word = word.lower().strip()
    if not word:
        return 0
        
    # Exceptional short words
    if len(word) <= 3:
        return 1
        
    # Count vowel groups
    vowels = "aeiouy"
    count = 0
    prev_char_was_vowel = False
    
    for char in word:
        is_vowel = char in vowels
        if is_vowel and not prev_char_was_vowel:
            count += 1
        prev_char_was_vowel = is_vowel
        
    # Deduct common silent letters at the end
    if word.endswith("e"):
        count -= 1
    if word.endswith("es") or word.endswith("ed"):
        # but do not deduct if ending with le
        if not word.endswith("le"):
            count -= 1
            
    # Guarantee at least 1 syllable
    return max(1, count)


def flesch_kincaid_grade(doc) -> float:
    """Calculates Flesch-Kincaid Grade Level on a spaCy doc."""
    sentences = list(doc.sents)
    if not sentences:
        return 0.0
        
    words = [token for token in doc if not token.is_punct and not token.is_space]
    if not words:
        return 0.0
        
    word_count = len(words)
    sent_count = len(sentences)
    
    syllable_count = sum(count_syllables(w.text) for w in words)
    
    # Standard formula
    fk = (0.39 * (word_count / sent_count)) + (11.8 * (syllable_count / word_count)) - 15.59
    return round(max(0.0, fk), 2)


def vocabulary_density(doc) -> float:
    """Information vocabulary density: unique lemma ratio among content tokens."""
    words = [t.lemma_.lower() for t in doc if not t.is_stop and not t.is_punct and not t.is_space]
    if not words:
        return 0.0
    return round(1.0 - (len(set(words)) / len(words)), 3)


def calculate_composite_score(fk: float, density: float, avg_len: float) -> float:
    """Maps reading ease and information density to a composite load scale (0.0 to 1.0)."""
    # Normalize metrics to 0-1 range
    fk_norm = min(fk / 18.0, 1.0)           # Grade 18+ = 1.0
    density_norm = density                  # Already 0-1
    len_norm = min(avg_len / 35.0, 1.0)     # 35+ words = 1.0
    
    # Weighted average: 40% Grade Level, 30% density, 30% sentence length
    composite = (0.4 * fk_norm) + (0.3 * density_norm) + (0.3 * len_norm)
    return round(min(max(composite, 0.05), 1.0), 2)


def score_to_color(score: float) -> str:
    """Maps composite score to color codes matching SwiftUI DesignTokens."""
    if score <= 0.35:
        return "#4CAF50" # Green (success)
    elif score <= 0.65:
        return "#FFC107" # Yellow (warning)
    elif score <= 0.82:
        return "#FF9800" # Orange (info/alert)
    else:
        return "#F44336" # Red (error)


def analyze_text(text: str) -> List[Dict[str, Any]]:
    """Splits text into paragraphs and calculates individual complexity dimensions."""
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    results = []
    
    for idx, para_text in enumerate(paragraphs):
        # Strip markdown headers for pure reading analysis
        clean_text = re.sub(r"^#+\s+", "", para_text)
        
        doc = nlp(clean_text)
        fk = flesch_kincaid_grade(doc)
        density = vocabulary_density(doc)
        
        sentences = list(doc.sents)
        words = [t for t in doc if not t.is_punct and not t.is_space]
        avg_len = len(words) / len(sentences) if sentences else 0.0
        
        composite = calculate_composite_score(fk, density, avg_len)
        color = score_to_color(composite)
        
        results.append({
            "paragraphIndex": idx,
            "text": para_text,
            "fleschKincaid": fk,
            "tokenDensity": density,
            "compositeScore": composite,
            "color": color
        })
        
    return results
