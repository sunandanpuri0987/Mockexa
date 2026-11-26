from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class AptitudeQuestion:
    id: str
    prompt: str
    category: str
    difficulty: int
    options: tuple[str, str, str, str]
    correct_index: int
    explanation: str

    def public_dict(self) -> dict:
        return {
            "id": self.id,
            "prompt": self.prompt,
            "category": self.category,
            "difficulty": self.difficulty,
            "options": list(self.options),
        }


QUESTIONS = (
    # Quantitative Aptitude
    AptitudeQuestion("quant-percent", "What is 15% of 240?", "Quantitative Aptitude", 1, ("24", "30", "36", "40"), 2, "15% of 240 = 0.15 × 240 = 36."),
    AptitudeQuestion("quant-ratio", "The ratio of two numbers is 3:5 and their sum is 64. What is the smaller number?", "Quantitative Aptitude", 2, ("18", "24", "32", "40"), 1, "There are 8 ratio parts. Each part is 64 ÷ 8 = 8, so the smaller number is 3 × 8 = 24."),
    AptitudeQuestion("quant-interest", "Find the simple interest on ₹5,000 at 8% per annum for 2 years.", "Quantitative Aptitude", 2, ("₹400", "₹600", "₹800", "₹1,000"), 2, "Simple interest = PRT/100 = 5000 × 8 × 2 / 100 = ₹800."),
    AptitudeQuestion("quant-average", "What is the average of 12, 15, 18, 21 and 24?", "Quantitative Aptitude", 1, ("16", "17", "18", "19"), 2, "Their sum is 90 and 90 ÷ 5 = 18."),
    AptitudeQuestion("quant-speed", "A car covers 180 km in 3 hours at a constant speed. What is its speed?", "Quantitative Aptitude", 1, ("45 km/h", "50 km/h", "60 km/h", "90 km/h"), 2, "Speed = distance ÷ time = 180 ÷ 3 = 60 km/h."),
    AptitudeQuestion("quant-work", "A can complete a job in 12 days and B in 18 days. Working together, how long will they take?", "Quantitative Aptitude", 3, ("6 days", "7.2 days", "8 days", "15 days"), 1, "Combined rate = 1/12 + 1/18 = 5/36 job/day, so time = 36/5 = 7.2 days."),
    AptitudeQuestion("quant-discount", "An item marked at ₹800 is sold at a 10% discount. What is the selling price?", "Quantitative Aptitude", 1, ("₹700", "₹720", "₹740", "₹780"), 1, "The discount is ₹80, so the selling price is ₹800 − ₹80 = ₹720."),
    AptitudeQuestion("quant-compound", "What is the amount on ₹10,000 compounded annually at 10% for 2 years?", "Quantitative Aptitude", 2, ("₹11,000", "₹11,200", "₹12,000", "₹12,100"), 3, "Amount = 10000 × 1.1² = ₹12,100."),
    AptitudeQuestion("quant-train", "A train moving at 72 km/h crosses a pole in 10 seconds. What is the train's length?", "Quantitative Aptitude", 3, ("100 m", "150 m", "200 m", "720 m"), 2, "72 km/h = 20 m/s. Distance in 10 seconds = 20 × 10 = 200 m."),
    AptitudeQuestion("quant-probability", "What is the probability of rolling a number greater than 4 on a fair six-sided die?", "Quantitative Aptitude", 2, ("1/6", "1/3", "1/2", "2/3"), 1, "The favourable outcomes are 5 and 6: 2/6 = 1/3."),

    # Logical Reasoning
    AptitudeQuestion("logic-sequence", "Find the next number: 2, 6, 12, 20, 30, ?", "Logical Reasoning", 2, ("36", "40", "42", "44"), 2, "The terms are n(n+1): 1×2, 2×3, …, 5×6. The next is 6×7 = 42."),
    AptitudeQuestion("logic-odd", "Which number does not belong: 16, 25, 36, 49, 63?", "Logical Reasoning", 1, ("25", "36", "49", "63"), 3, "16, 25, 36 and 49 are consecutive perfect squares; 63 is not a perfect square."),
    AptitudeQuestion("logic-code", "If CAT is coded as DBU by shifting every letter forward once, how is DOG coded?", "Logical Reasoning", 1, ("EPH", "EPG", "FPH", "EOH"), 0, "D→E, O→P and G→H, giving EPH."),
    AptitudeQuestion("logic-direction", "Riya walks 4 km north and then 3 km east. In which direction is she from her starting point?", "Logical Reasoning", 1, ("North-west", "North-east", "South-east", "East"), 1, "She is both north and east of the start, so the direction is north-east."),
    AptitudeQuestion("logic-syllogism", "All developers are logical. Some logical people are creative. Which conclusion must follow?", "Logical Reasoning", 3, ("All creative people are developers", "Some developers are creative", "No developer is creative", "No definite relation between developers and creative people"), 3, "The two groups may overlap, but the statements do not force any developer to be creative."),
    AptitudeQuestion("logic-ranking", "In a class of 40 students, Aman is 12th from the top. What is his rank from the bottom?", "Logical Reasoning", 2, ("27th", "28th", "29th", "30th"), 2, "Bottom rank = total − top rank + 1 = 40 − 12 + 1 = 29."),
    AptitudeQuestion("logic-pairs", "Find the next pair: AZ, BY, CX, ?", "Logical Reasoning", 2, ("DV", "DW", "DX", "EV"), 1, "The first letter moves forward A, B, C, D while the second moves backward Z, Y, X, W."),
    AptitudeQuestion("logic-family", "Maya is Ravi's mother. Ravi is Neha's brother. How is Maya related to Neha?", "Logical Reasoning", 1, ("Sister", "Aunt", "Mother", "Grandmother"), 2, "Ravi and Neha are siblings, so Ravi's mother Maya is also Neha's mother."),
    AptitudeQuestion("logic-day", "If today is Monday, what day will it be after 45 days?", "Logical Reasoning", 2, ("Tuesday", "Wednesday", "Thursday", "Friday"), 2, "45 leaves a remainder of 3 when divided by 7; three days after Monday is Thursday."),
    AptitudeQuestion("logic-order", "P is taller than Q. Q is taller than R. S is taller than P. Who is the tallest?", "Logical Reasoning", 1, ("P", "Q", "R", "S"), 3, "The order is S > P > Q > R, so S is tallest."),

    # Verbal Ability
    AptitudeQuestion("verbal-synonym", "Choose the closest synonym of ‘concise’.", "Verbal Ability", 1, ("Brief", "Unclear", "Detailed", "Repetitive"), 0, "Concise means brief while still expressing the necessary information."),
    AptitudeQuestion("verbal-antonym", "Choose the antonym of ‘scarce’.", "Verbal Ability", 1, ("Rare", "Limited", "Abundant", "Costly"), 2, "Scarce means insufficient or rare; abundant means plentiful."),
    AptitudeQuestion("verbal-grammar", "Choose the grammatically correct sentence.", "Verbal Ability", 2, ("Neither of the answers are correct.", "Neither of the answers is correct.", "Neither answers is correct.", "Neither of answer are correct."), 1, "‘Neither’ is singular here, so it takes the singular verb ‘is’."),
    AptitudeQuestion("verbal-analogy", "Book is to reading as song is to ____.", "Verbal Ability", 1, ("Writing", "Listening", "Drawing", "Speaking"), 1, "A book is read; a song is listened to."),
    AptitudeQuestion("verbal-fill", "____ the task was difficult, the team completed it on time.", "Verbal Ability", 2, ("Because", "Although", "Unless", "Therefore"), 1, "‘Although’ correctly introduces a contrast between difficulty and timely completion."),
    AptitudeQuestion("verbal-error", "Identify the incorrect part: ‘Each of the players have submitted their form.’", "Verbal Ability", 2, ("Each of", "the players", "have submitted", "their form"), 2, "The subject ‘Each’ is singular, so ‘have submitted’ should be ‘has submitted’."),
    AptitudeQuestion("verbal-spelling", "Choose the correctly spelled word.", "Verbal Ability", 1, ("Accomodation", "Accommodation", "Acommodation", "Accommadation"), 1, "‘Accommodation’ has two c's and two m's."),
    AptitudeQuestion("verbal-passive", "Choose the correct passive form of: ‘The committee approved the proposal.’", "Verbal Ability", 2, ("The proposal approved the committee.", "The proposal was approved by the committee.", "The committee was approved by the proposal.", "The proposal has approving by the committee."), 1, "The object becomes the subject: ‘The proposal was approved by the committee.’"),
    AptitudeQuestion("verbal-idiom", "What does ‘once in a blue moon’ mean?", "Verbal Ability", 1, ("At night", "Very rarely", "Without warning", "At the right time"), 1, "The idiom means that something happens very rarely."),
    AptitudeQuestion("verbal-order", "Choose the most logical order: P: It began to rain. Q: We opened our umbrellas. R: Dark clouds gathered. S: We continued walking.", "Verbal Ability", 2, ("R-P-Q-S", "P-R-S-Q", "Q-P-R-S", "R-Q-P-S"), 0, "Clouds gather first, rain begins, umbrellas are opened, and then walking continues: R-P-Q-S."),

    # Data Interpretation
    AptitudeQuestion("di-sales-total", "Quarterly sales (₹ lakh) were Q1=20, Q2=25, Q3=30, Q4=35. What were total annual sales?", "Data Interpretation", 1, ("₹100 lakh", "₹105 lakh", "₹110 lakh", "₹115 lakh"), 2, "20 + 25 + 30 + 35 = ₹110 lakh."),
    AptitudeQuestion("di-sales-growth", "Sales increased from 200 units to 250 units. What was the percentage increase?", "Data Interpretation", 2, ("20%", "25%", "40%", "50%"), 1, "Increase = 50. Percentage increase = 50/200 × 100 = 25%."),
    AptitudeQuestion("di-students", "A survey has 120 engineering, 80 commerce and 50 arts students. What percentage are engineering students?", "Data Interpretation", 2, ("40%", "48%", "50%", "60%"), 1, "Total = 250. Engineering share = 120/250 × 100 = 48%."),
    AptitudeQuestion("di-profit", "A company's revenue is ₹8 lakh and expenditure is ₹6.4 lakh. Profit is what percentage of expenditure?", "Data Interpretation", 3, ("20%", "25%", "32%", "40%"), 1, "Profit = 1.6 lakh. As a percentage of expenditure: 1.6/6.4 × 100 = 25%."),
    AptitudeQuestion("di-average-output", "A factory produced 80, 100, 120 and 140 units over four days. What was the average daily output?", "Data Interpretation", 1, ("100", "105", "110", "115"), 2, "Total output is 440; 440 ÷ 4 = 110 units."),
    AptitudeQuestion("di-pie", "In a budget, rent is 30%, food 25%, travel 15% and savings 20%. What percentage remains for other expenses?", "Data Interpretation", 1, ("5%", "10%", "15%", "20%"), 1, "Listed shares total 90%, leaving 10% for other expenses."),
    AptitudeQuestion("di-ratio", "A table shows Product A sold 150 units and Product B sold 250 units. What is the ratio A:B in simplest form?", "Data Interpretation", 1, ("2:3", "3:5", "5:3", "15:20"), 1, "150:250 simplifies by dividing both values by 50, giving 3:5."),
    AptitudeQuestion("di-median", "Monthly orders were 40, 55, 50, 65 and 45. What is the median?", "Data Interpretation", 2, ("45", "50", "51", "55"), 1, "Sorted values are 40, 45, 50, 55, 65; the middle value is 50."),
    AptitudeQuestion("di-change", "Website visits were 1,000 on Monday, 1,200 on Tuesday and 900 on Wednesday. By how many did visits fall from Tuesday to Wednesday?", "Data Interpretation", 1, ("100", "200", "300", "400"), 2, "The fall was 1,200 − 900 = 300 visits."),
    AptitudeQuestion("di-share", "A company has 80 employees in Engineering, 40 in Sales, 30 in Operations and 50 in Support. What share work in Support?", "Data Interpretation", 2, ("20%", "25%", "30%", "40%"), 1, "Total employees = 200. Support share = 50/200 × 100 = 25%."),
)

CATEGORIES = tuple(sorted({question.category for question in QUESTIONS}))
