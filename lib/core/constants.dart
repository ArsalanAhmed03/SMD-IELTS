import 'package:flutter/material.dart';

// Spacing
const double kPageHPad = 16.0;
const double kSectionSpacing = 20.0;
const double kCardRadius = 14.0;

const Color kBrandPrimary = Color(0xFFEF473A);       
const Color kBrandPrimaryDark = Color(0xFFD63E32);   
const Color kBrandAccent = Color(0xFFEF473A);         

// Surfaces and neutrals – clean white layout
const Color kSurface = Colors.white;                 
const Color kCard = Colors.white;                    
const Color kTextPrimary = Color(0xFF1A1A1A);        
const Color kTextSecondary = Color(0xFF555555);      
const Color kSoftDivider = Color(0xFFE5E5E5);        

const Color kHeroGradStart = Color(0xFFFF6A5B);
const Color kHeroGradEnd = Color(0xFFEF473A);

enum QuestionType { mcq, gapFill, shortText, essay, speaking }

// Exam default durations (minutes)
const int kListeningMinutes = 30;
const int kReadingMinutes = 60;
const int kWritingMinutes = 60;
const int kSpeakingMinutes = 15;
